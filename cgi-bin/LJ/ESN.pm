package LJ::ESN;
use strict;
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::Event
                      LJ::Subscription
                      );

use Data::Dumper;

our $MAX_FILTER_SET = 5_000;

sub schwartz_capabilities {
    return (
            "LJ::Worker::FiredEvent",         # step 1: can go to 2 or 4
            "LJ::Worker::FindSubsByCluster",  # step 2: can go to 3 or 4
            "LJ::Worker::FilterSubs",         # step 3: goes to step 4
            "LJ::Worker::ProcessSub",         # step 4
            );
}

# class method
sub process_fired_events {
    my $class = shift;
    my %opts = @_;
    my $verbose = delete $opts{verbose};
    croak("Unknown options") if keys %opts;
    croak("Can't call in web context") if LJ::is_web_context();

    my $sclient = LJ::theschwartz();
    foreach my $cap (schwartz_capabilities()) {
        $sclient->can_do($cap);
    }
    $sclient->set_verbose($verbose);
    $sclient->work_until_done;
}

sub jobs_of_unique_matching_subs {
    my ($class, $evt, @subs) = @_;
    my %has_done = ();
    my @subjobs;

    my $params = $evt->raw_params;

    if ($ENV{DEBUG}) {
        warn "jobs of unique subs (@subs) matching event (@$params)\n";
    }

    foreach my $s (grep { $evt->matches_filter($_) } @subs) {
        next if $has_done{$s->unique}++;
        push @subjobs, TheSchwartz::Job->new(
                                             funcname => 'LJ::Worker::ProcessSub',
                                             arg      => [
                                                          $s->userid + 0,
                                                          $s->id     + 0,
                                                          $params           # arrayref of event params
                                                          ],
                                             );
    }
    return @subjobs;
}

# this is phase1 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::FiredEvent;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my $evt = eval { LJ::Event->new_from_raw_params(@$a) };

    if ($ENV{DEBUG}) {
        warn "FiredEvent for $evt (@$a)\n";
    }

    unless ($evt) {
        $job->failed;
        return;
    }

    # step 1:  see if we can split this into a bunch of ProcessSub directly.
    # we can only do this if A) all clusters are up, and B) subs is reasonably
    # small.  say, under 5,000.
    my $split_per_cluster = 0;  # bool: died or hit limit, split into per-cluster jobs
    my @subs;
    foreach my $cid (@LJ::CLUSTERS) {
        my @more_subs = eval { $evt->subscriptions(cluster => $cid,
                                                   limit   => $LJ::ESN::MAX_FILTER_SET - @subs) };
        if ($@) {
            # if there were errors (say, the cluster is down), abort!
            # that is, abort the fast path and we'll resort to
            # per-cluster scanning
            $split_per_cluster = "some_error";
            last;
        }

        push @subs, @more_subs;
        if (@subs > $LJ::ESN::MAX_FILTER_SET) {
            $split_per_cluster = "hit_max";
            warn "Hit max!  over $LJ::ESN::MAX_FILTER_SET = @subs\n" if $ENV{DEBUG};
            last;
        }
    }

    my $params = $evt->raw_params;

    if ($ENV{DEBUG}) {
        warn "split_per_cluster=[$split_per_cluster], params=[@$params]\n";
    }

    # this is the slow/safe/on-error/lots-of-subscribers path
    if ($LJ::_T_ESN_FORCE_P1_P2 || $split_per_cluster) {
        my @subjobs;
        foreach my $cid (@LJ::CLUSTERS) {
            push @subjobs, TheSchwartz::Job->new(
                                                 funcname => 'LJ::Worker::FindSubsByCluster',
                                                 arg      => [ $cid, $params ],
                                                 );
        }
        return $job->replace_with(@subjobs);
    }

    # the fast path, filter those max 5,000 subscriptions down to ones that match,
    # then split right into processing those notification methods
    my @subjobs = LJ::ESN->jobs_of_unique_matching_subs($evt, @subs);

    return $job->replace_with(@subjobs);
}


sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

# this is phase2 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::FindSubsByCluster;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($cid, $e_params) = @$a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) } or
        die "Couldn't load event: $@";
    my $dbch = LJ::get_cluster_master($cid) or
        die "Couldn't connect to cluster \#cid $cid";

    my @subs = $evt->subscriptions(cluster => $cid);

    if ($ENV{DEBUG}) {
        warn "for event (@$e_params), find subs by cluster = [@subs]\n";
    }

    # fast path:  job from phase2 to phase4, skipping filtering.
    if (@subs <= $LJ::ESN::MAX_FILTER_SET && ! $LJ::_T_ESN_FORCE_P2_P3) {
        my @subjobs = LJ::ESN->jobs_of_unique_matching_subs($evt, @subs);
        warn "fast path:  subjobs=@subjobs\n" if $ENV{DEBUG};
        return $job->replace_with(@subjobs);
    }

    # slow path:  too many jobs to filter at once.  group it into sets
    # of 5,000 (MAX_FILTER_SET) for separate filtering (phase3)
    # NOTE: we have to take care not to split subscriptions spanning
    # set boundaries with the same userid (ownerid).  otherwise dup
    warn "Going on the P2 P3 slow path...\n" if $ENV{DEBUG};

    # checking is bypassed for that user.
    my %by_userid;
    foreach my $s (@subs) {
        push @{$by_userid{$s->userid} ||= []}, $s;
    }

    my @subjobs;
    # now group into sets of 5,000:
    while (%by_userid) {
        my @set;
      BUILD_SET:
        while (%by_userid && @set < $LJ::ESN::MAX_FILTER_SET) {
            my $finish_set = 0;
          UID:
            foreach my $uid (keys %by_userid) {
                my $subs = $by_userid{$uid};
                my $size = scalar @$subs;
                my $remain = $LJ::ESN::MAX_FILTER_SET - @set;

                # if a user for some reason has more than 5,000 matching subscriptions,
                # uh, skip them.  that's messed up.
                if ($size > $LJ::ESN::MAX_FILTER_SET) {
                    delete $by_userid{$uid};
                    next UID;
                }

                # if this user's subscriptions don't fit into the @set,
                # move on to the next user
                if ($size > $remain) {
                    $finish_set = 1;
                    next UID;
                }

                # add user's subs to this set and delete them.
                push @set, @$subs;
                delete $by_userid{$uid};
            }
            last BUILD_SET if $finish_set;
        }

        # $sublist is [ [userid, subid]+ ]
        my $sublist = [ map { [ $_->userid + 0, $_->id + 0 ] } @set ];
        push @subjobs, TheSchwartz::Job->new(
                                             funcname => 'LJ::Worker::FilterSubs',
                                             arg      => [ $e_params, $sublist ],
                                             );
    }

    warn "Filter sub jobs: [@subjobs]\n" if $ENV{DEBUG};
    return $job->replace_with(@subjobs);
}

# this is phase3 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::FilterSubs;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($e_params, $sublist) = @$a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) } or
        die "Couldn't load event: $@";

    my @subjobs;
    foreach my $sp (@$sublist) {
        my ($userid, $subid) = @$sp;
        my $u = LJ::load_userid($userid)
            or die "Failed to load userid: $userid\n";

        # TODO: discern difference between cluster not up and subscription
        #       having been deleted
        my $subsc = LJ::Subscription->new_by_id($u, $subid)
            or next;

        next unless $evt->matches_filter($subsc);
        push @subjobs, TheSchwartz::Job->new(
                                             funcname => 'LJ::Worker::ProcessSub',
                                             arg      => [
                                                          $userid,
                                                          $subid,
                                                          $e_params           # arrayref of event params
                                                          ],
                                             );
    }

    return $job->replace_with(@subjobs) if @subjobs;
    $job->completed;
}

# this is phase4 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::ProcessSub;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($userid, $subid, $eparams) = @$a;
    my $u     = LJ::load_userid($userid);
    my $evt   = LJ::Event->new_from_raw_params(@$eparams);
    my $subsc = LJ::Subscription->new_by_id($u, $subid);

    # if the subscription doesn't exist anymore, we're done here
    # (race: if they delete the subscription between when we start processing
    # events and when we get here, LJ::Subscription->new_by_id will return undef)
    # We won't reach here if we get DB errors because new_by_id will die, so we're
    # safe to mark the job completed and return.
    return $job->completed unless $subsc;

    # if debugging schwartz job ids, stick the job id
    # in the subscription object so it can access it
    $subsc->{_sch_jobid} = $job->jobid if $LJ::DEBUG{'esn_notif_include_sch_ids'};

    # TODO: do inbox notification method here, first.

    # NEXT: do sub's ntypeid, unless it's inbox, then we're done.
    $subsc->process($evt)
        or die "Failed to process notification method for userid=$userid/subid=$subid, evt=[@$eparams]\n";
    $job->completed;
}

sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

1;
