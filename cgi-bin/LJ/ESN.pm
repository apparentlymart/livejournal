package LJ::ESN;
use strict;
use Carp qw(croak);
use LJ::Event;
use LJ::Subscription;
use Sys::Hostname qw/hostname/;
use Data::Dumper;

our $MAX_FILTER_SET = 5_000;

sub schwartz_capabilities {
    return (
            "LJ::Worker::FiredEvent",         # step 1: can go to 2 or 4
            "LJ::Worker::FiredMass",          # alternative step 1: can go to 4
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
    my ($class, $evt, $subs, $debug_args) = @_;
    my %has_done = ();
    $debug_args ||= {};
    my @subjobs;

    my $params = $evt->raw_params;

    if ($ENV{DEBUG}) {
        warn "jobs of unique subs (@$subs) matching event (@$params)\n";
    }

    my @subs_filtered;
    
    foreach my $sub (@$subs) {
        next unless defined $sub;
        next unless $evt->available_for_user($sub->owner);
        next unless $evt->matches_filter($sub);

        push @subs_filtered, $sub;
    }
    
    foreach my $s (@subs_filtered) {
        next if $has_done{$s->unique}++;
        push @subjobs, TheSchwartz::Job->new(
            funcname => 'LJ::Worker::ProcessSub',
            arg      => {
                'userid'    => $s->userid + 0,
                'subdump'   => $s->dump,
                'e_params'  => $params,
                %$debug_args,
            },
        );
    }
    return @subjobs;
}

## class method
## Returns list ('debug_info' => \@info)
## May append signature of the current job to the @info
sub _get_debug_args {
    my $worker_class = shift;
    my $job = shift;
    my $append_current_job = shift;
    my $extra_arg = shift;

    return unless $LJ::DEBUG{esn_email_headers};
    
    my $arg = $job->arg;
    my @info = (ref $arg eq 'HASH' && $arg->{'debug_info'}) ? @{ $arg->{'debug_info'} } : ();
   
    if ($append_current_job) {
        my $jobid = $job->jobid;
        my $failures = $job->failures;
        my $grabbed_until = $job->grabbed_until;
        my $time = time;
        my ($short_class_name) = ($worker_class =~ /::(\w+)$/);
        my $host = hostname();  ## this is not expensive, since Sys::Hostname caches result
        push @info, "c=$short_class_name j=$jobid f=$failures t=$time g=$grabbed_until p=$$ h=$host $extra_arg";
    }

    return ('debug_info' => \@info); 
}


# this is phase1 of processing.  see doc/server/ljp.int.esn.html
package LJ::Worker::FiredEvent;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my $e_params = (ref $a eq 'HASH') ? $a->{'event_params'} : $a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) };

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
                                                   limit   => $LJ::ESN::MAX_FILTER_SET - @subs + 1) };
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

    my %debug_args = LJ::ESN::_get_debug_args($class, $job, 1, "ep=" . join(":", @$e_params));

    # this is the slow/safe/on-error/lots-of-subscribers path
    if ($ENV{FORCE_P1_P2} || $LJ::_T_ESN_FORCE_P1_P2 || $split_per_cluster) {
        my @subjobs;
        foreach my $cid (@LJ::CLUSTERS) {
            push @subjobs, TheSchwartz::Job->new(
                funcname => 'LJ::Worker::FindSubsByCluster',
                arg      => { 
                    'cid'       => $cid, 
                    'e_params'  => $params,
                    %debug_args,
                },
            );
        }
        return $job->replace_with(@subjobs);
    } else {
        # the fast path, filter those max 5,000 subscriptions down to ones that match,
        # then split right into processing those notification methods
        my @subjobs = LJ::ESN->jobs_of_unique_matching_subs($evt, \@subs, \%debug_args);
        return $job->replace_with(@subjobs);
    }
}


sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

package LJ::Worker::FiredMass;
use base 'TheSchwartz::Worker';

# LJ::Worker::FiredMass: a worker to process the "mass" subscriptions,
# including the OfficialPost ones. these need special handling, because handling
# them the usual way can get us to the system swap quickly, which is a bad
# thing.
#
# $arg = {
#     # mandatory: an LJ::Event object detailing what happened
#     'evt' => LJ::Event::OfficialPost->new($entry),
#
#     # optional: only search through subscriptions of the users with
#     # userid > minuid; this parameter is used by the worker to "chain"
#     # itself, each instance only processing about $LJ::ESN_OFFICIALPOST_BATCH
#     # subscriptions
#     'minuid' => 15,
#
#     # optional: a cluster to search on
#     # in case it's not specified, the job replaces itself with
#     # scalar(@LJ::CLUSTERS) job, each handling a single cluster
#     'cid' => 3,
# };
sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my %arg = %$a;

    # check arguments
    my $evt = $arg{'evt'};
    die "expecting $evt to be an LJ::Event object"
        unless $evt->isa("LJ::Event");
    my $etypeid = $evt->etypeid;

    my $minuid = $arg{'minuid'} || 0;
    my $cid = $arg{'cid'};

    # oh no, there is no cluster, so we don't know where to search... yet. :)
    # spawn additional jobs to search through the clusters.
    unless ($cid) {
        my @jobs;
        foreach my $cid2 (@LJ::CLUSTERS) {
            push @jobs, TheSchwartz::Job->new(
                'funcname' => __PACKAGE__,
                'arg' => {
                    'evt' => $evt,
                    'cid' => $cid2,
                    'minuid' => $minuid,
                    LJ::ESN::_get_debug_args($class, $job, 1, "cid=$cid2"),   
                },
            );
        }
        return $job->replace_with(@jobs);
    }

    # at this point, we have a $cid, yay.

    my $limit = $LJ::ESN_OFFICIALPOST_BATCH;

    # here's how selecting works:
    # the first query gets no more than $limit subs rows; after we get the
    # result, we *remove* the greatest userid from it and then use the
    # second query to re-fetch rows corresponding to that userid
    #
    # in more technical terms, @process_batch stores the selection result,
    # @buffer is, well, a buffer of subs that were fetched from the DB but
    # have not yet been transferred to @process_batch.
    #
    # @buffer is flushed when $row->{'userid'} changes.
    #
    # there's also a trick here: we specify journalid=0 deliberately to ensure
    # that the (`etypeid`,`journalid`,`userid`) key is being used.
    my (@process_batch, @buffer, $lastuid);

    my $dbh = LJ::get_cluster_reader($cid) ||
        die "cannot get cluster reader for cluster $cid";

    # FIRST QUERY: get $limit rows, ordered by userid
    my $res = $dbh->selectall_arrayref(qq{
        SELECT *
        FROM subs
        WHERE etypeid=? AND journalid = 0 AND userid > ?
        ORDER BY userid
        LIMIT $limit
    }, { Slice => {} }, $etypeid, $minuid);

    foreach my $row (@$res) {
        if ($row->{'userid'} != $lastuid) {
            push @process_batch, @buffer;
            @buffer = ();
        }

        $lastuid = $row->{'userid'};
        push @buffer, $row;
    }

    # SECOND QUERY: get all rows matching the greatest userid we've found in
    # the first query.
    $res = $dbh->selectall_arrayref(qq{
        SELECT *
        FROM subs
        WHERE etypeid=? AND journalid = 0 AND userid = ?
    }, { Slice => {} }, $etypeid, $lastuid);

    foreach my $row (@$res) {
        push @process_batch, $row;
    }

    # uh, there's nothing left to process, so we can be happy.
    return $job->completed unless @process_batch;

    # at this point, we need to spawn the following jobs:
    #
    # 1). ourselves, to ensure that the other users are going to receive their
    #     subs.
    # 2). ProcessSub for each sub we've already found that is more-or-less
    #     valid (active / available_for_user), to ensure that people actually
    #     get notified.
    my @jobs;

    # OURSELVES
    push @jobs, TheSchwartz::Job->new(
        'funcname' => __PACKAGE__,
        'arg' => {
            'evt' => $evt,
            'cid' => $cid,
            'minuid' => $lastuid,
            
            ## keep exisiting debug args, but don't append signature of the current job,
            ## because there may be up to 1000+ 'FiredMass' consequent jobs before 'ProcessSub' job
            LJ::ESN::_get_debug_args($class, $job), 
        },
    );

    # PROCESSSUB
    foreach my $row (@process_batch) {
        my $sub = LJ::Subscription->new_from_row($row);

        next unless $sub->active;
        next unless $sub->available_for_user($sub->owner);

        my $params = $evt->raw_params;
        push @jobs, TheSchwartz::Job->new(
            'funcname' => 'LJ::Worker::ProcessSub',
            'arg' => {
                'userid'    => $sub->userid, 
                'subdump'   => $sub->dump,
                'e_params'  => $params,
                LJ::ESN::_get_debug_args($class, $job, 1, "min=$minuid"),
            },
        );
    }

    # we're done here, but there is staff to do; the other workers will
    # pick that up. so long, and thanks for all the fish.
    return $job->replace_with(@jobs);
}

# this is phase2 of processing.  see doc/server/ljp.int.esn.html
package LJ::Worker::FindSubsByCluster;
use base 'TheSchwartz::Worker';

sub do_work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($cid, $e_params) = (ref $a eq 'HASH') ? ($a->{'cid'}, $a->{'e_params'}) : @$a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) } or
        die "Couldn't load event: $@";
    my $dbch = LJ::get_cluster_master($cid) or
        die "Couldn't connect to cluster \#cid $cid";

    my @subs = $evt->subscriptions(cluster => $cid);

    if ($ENV{DEBUG}) {
        warn "for event (@$e_params), find subs by cluster = [@subs]\n";
    }

    # fast path:  job from phase2 to phase4, skipping filtering.
    if (@subs <= $LJ::ESN::MAX_FILTER_SET && ! $LJ::_T_ESN_FORCE_P2_P3 && ! $ENV{FORCE_P2_P3}) {
        my %debug_args = LJ::ESN::_get_debug_args($class, $job, 1, "cid=$cid fast=true");
        my @subjobs = LJ::ESN->jobs_of_unique_matching_subs($evt, \@subs, \%debug_args);
        warn "fast path: subjobs=@subjobs\n" if $ENV{DEBUG};
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

        # $sublist is [ [userid, subdump]+ ]. also, pass clusterid through
        # to filtersubs so we can check that we got a subscription for that
        # user from the right cluster. (to avoid user moves with old data
        # on old clusters from causing duplicates). easier to do it there
        # than here, to avoid a load_userids call.
        my $sublist = [ map { [ $_->userid + 0, $_->dump ] } @set ];
        push @subjobs, TheSchwartz::Job->new(
            funcname => 'LJ::Worker::FilterSubs',
            arg      => { 
                'e_params'  => $e_params, 
                'sublist'   => $sublist, 
                'cid'       => $cid,
                LJ::ESN::_get_debug_args($class, $job, 1, "cid=$cid fast=false"),
            },
        );
    }

    warn "Filter sub jobs: [@subjobs]\n" if $ENV{DEBUG};
    return $job->replace_with(@subjobs);
}

sub work {
    my ($class, $job) = @_;

    my $pid = fork;
    
    ##
    ## list of exit codes of child processes:
    ## 0 - job didn't do the work (did_something==0)
    ## 1 - did_something>0 (it's boolean value, actually)
    ## 2 - exception was thrown, reason and message are lost :(
    ##
    ## This is a hack, the more solid solution will be later. 
    ## 
    if (!defined $pid) {
        die "fork failed: $!";
    } elsif ($pid) {
        
        ## Must use default CHLD handler, otherwise, waitpid will return -1
        ## and no exit status of child process can be collected
        local $SIG{CHLD}; 
        
        my $wpid = waitpid($pid, 0);
        if ($wpid!=$pid) {
            die "Something strange: waitpid($pid,0) returned $wpid";
        }
        my $status = $? >> 8;
        if ($status==0 || $status==1) {
            return $job->did_something($status);
        } elsif ($status==2) {
            die "Job died";
        } else {
            die "Job did something strange";
        }
    } else {
        eval {
            $class->do_work($job);
        };
        if ($@) {
            warn $@;
            exit 2;
        } else {
            exit( $job->did_something ? 1 : 0 );
        }
    }
}


# this is phase3 of processing.  see doc/server/ljp.int.esn.html
package LJ::Worker::FilterSubs;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($e_params, $sublist, $cid) = (ref $a eq 'HASH') ? ($a->{'e_params'}, $a->{'sublist'}, $a->{'cid'}) : @$a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) } or
        die "Couldn't load event: $@";

    my @subs;
    foreach my $sp (@$sublist) {
        my ($userid, $subdump) = @$sp;
        my $u = LJ::load_userid($userid)
            or die "Failed to load userid: $userid\n";

        # check that we fetched the subscription from the cluster the user
        # is currently on. (and not, eg, a cluster they were moved from)
        next if $cid && $u->clusterid != $cid;

        # TODO: discern difference between cluster not up and subscription
        #       having been deleted
        my $subsc = LJ::Subscription->new_from_dump($u, $subdump)
            or next;

        push @subs, $subsc;
    }

    my %debug_args = LJ::ESN::_get_debug_args($class, $job, 1, "cid=$cid sl=$#$sublist");
    my @subjobs = LJ::ESN->jobs_of_unique_matching_subs($evt, \@subs, \%debug_args);
    return $job->replace_with(@subjobs) if @subjobs;
    $job->completed;
}

# this is phase4 of processing.  see doc/server/ljp.int.esn.html
package LJ::Worker::ProcessSub;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($userid, $subdump, $eparams) = (ref $a eq 'HASH') ? ($a->{'userid'}, $a->{'subdump'}, $a->{'e_params'}) : @$a;
    my $u     = LJ::load_userid($userid);
    my $evt   = LJ::Event->new_from_raw_params(@$eparams);
    my $subsc = LJ::Subscription->new_from_dump($u, $subdump);

    # if the subscription doesn't exist anymore, we're done here
    # (race: if they delete the subscription between when we start processing
    # events and when we get here, LJ::Subscription->new_by_id will return undef)
    # We won't reach here if we get DB errors because new_by_id will die, so we're
    # safe to mark the job completed and return.
    return $job->completed unless $subsc;

    # if the user deleted their account (or otherwise isn't visible), bail
    return $job->completed unless $u->is_visible || $evt->is_significant;

    my %opts;
    if ($LJ::DEBUG{esn_email_headers}) {
        my $subscription_signature  = join(",", (
            "u=$subsc->{'userid'}",
            "s=$subsc->{'subid'}",
            "i=$subsc->{'is_dirty'}",
            "j=$subsc->{'journalid'}",
            "e=$subsc->{'etypeid'}",
            "a1=$subsc->{'arg1'}",
            "a2=$subsc->{'arg2'}",
            "n=$subsc->{'ntypeid'}",
            "c=$subsc->{'createtime'}",
            "x=$subsc->{'expiretime'}",
            "f=$subsc->{'flags'}",
        ));
        my (undef, $headers_list) = LJ::ESN::_get_debug_args($class, $job, 1, "uid=$userid sub=($subscription_signature)");
        my %debug_headers;
        foreach my $i (0..$#$headers_list) {
           $debug_headers{ sprintf('X-Esn-Debug-%02d', $i) } = $headers_list->[$i]; 
        }
        $opts{'_debug_headers'} = \%debug_headers;
    }

    if ($evt->isa('LJ::Event::OfficialPost')) {
        ## "TheSchwartz::Worker::SendEmail" tasks for events
        ## "OfficialPost" and "SupOfficialPost" should go to their database
        $opts{'_schwartz_role'} = $LJ::THESCHWARTZ_ROLE_MASS;
    }

    $subsc->process(\%opts, $evt)
        or die "Failed to process notification method for userid=$userid/subid=$subdump, evt=[@$eparams]\n";
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

