package LJ::ESN;
use strict;
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::Event
                      LJ::Subscription
                      );

# class method
sub process_fired_events {
    my $class = shift;
    croak("Can't call in web context") if LJ::is_web_context();

    my $sclient = LJ::theschwartz();
    $sclient->can_do("LJ::Worker::FiredEvent");
    $sclient->work_until_done;
}


# this is phase1 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::FiredEvent;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;

    my $evt = eval { LJ::Event->new_from_raw_params(@$a) };

    unless ($evt) {
        $job->failed;
        return;
    }

    # step 1:  see if we can split this into a bunch of ProcessSub directly.
    # we can only do this if A) all clusters are up, and B) subs is reasonably
    # small.  say, under 5,000.
    my $MAX_SPLIT_SIZE = 5_000;
    my $split_per_cluster = 0;  # bool: died or hit limit, split into per-cluster jobs
    my @subs;
    foreach my $cid (@LJ::CLUSTERS) {
        my @more_subs = eval { $evt->subscriptions(cluster => $cid,
                                                   limit   => $MAX_SPLIT_SIZE - @subs) };
        if ($@) {
            # if there were errors (say, the cluster is down), abort!
            # that is, abort the fast path and we'll resort to
            # per-cluster scanning
            $split_per_cluster = 1;
            last;
        }

        push @subs, @more_subs;
        if (@subs >= $MAX_SPLIT_SIZE) {
            $split_per_cluster = 1;
            last;
        }
    }

    my $params = $evt->raw_params;

    # this is the slow/safe/on-error/lots-of-subscribers path
    if ($split_per_cluster) {
        my @subjobs;
        foreach my $cid (@LJ::CLUSTERS) {
            push @subjobs, TheSchwartz::Job->new(
                                                 funcname => 'LJ::Worker::FindSubsByCluster',
                                                 arg      => [ $cid, $params ],
                                                 );
        }
        $job->replace_with(@subjobs);
        return;
    }

    # the fast path, filter those max 5,000 subscriptions down to ones that match,
    # then split right into processing those notification methods
    my @subjobs;
    foreach my $s (grep { $evt->matches_filter($_) } @subs) {
        push @subjobs, TheSchwartz::Job->new(
                                             funcname => 'LJ::Worker::ProcessSub',
                                             arg      => [
                                                          $s->userid + 0,
                                                          $s->id     + 0,
                                                          $params           # arrayref of event params
                                                          ],
                                             );
    }
    $job->replace_with(@subjobs);
}

sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

# this is phase4 of processing.  see doc/notes/esn-design.txt
package LJ::Worker::ProcessSub;
use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;
    my $a = $job->arg;
    my ($userid, $subid, $eparams) = @$a;
    my $u    = LJ::load_userid($userid);
    my $evt  = LJ::Event->new_from_raw_params(@$eparams);
    my $subs = LJ::Subscription->new_by_id($u, $subid);

    # TODO: do inbox notification method here, first.

    # NEXT: do sub's ntypeid, unless it's inbox, then we're done.
    my $nm = $subs->notification;
    $nm->notify($evt) or die "Failed to process notification method $nm for userid=$userid/subid=$subid, evt=[@$eparams]\n";
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
