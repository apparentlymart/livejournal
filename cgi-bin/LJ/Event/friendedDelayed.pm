package LJ::Event::friendedDelayed;

use strict;
use warnings;

use base 'LJ::Event';

# External modules
use Readonly;

# Internal modules
use LJ::ExtBlock;
use LJ::FriendQueue;

Readonly my $BASE_DELAY       => 1800;         # sec X
Readonly my $DELAY_LIMIT      => 24 * 60 * 60; # sec Z
Readonly my $DELAY_PER_ACTION => 600;          # sec Y

sub send {
    my ( $class, $action, $tou, $fromu ) = @_;
    die 'Expected parameter $tou in send()' unless $tou;
    die 'Expected parameter $fromu in send()' unless $fromu;
    die "Wrong action parameter: $action" unless $action =~ /^add|del|invite$/;

    ## delay values
    my $params = LJ::ExtBlock->load_by_id('antispam_params');
    my $values = $params ? LJ::JSON->from_json($params->blocktext) : {};
    my $reader_weight    = $fromu->get_reader_weight();

    my $max_delay;
    my $base_delay;
    my $delay_per_action;

    if ($action eq 'invite') {
        $values      ||= {};
        $values->{i} ||= {};

        $base_delay       = $values->{i}->{delay_time}  || $BASE_DELAY;
        $delay_per_action = $values->{i}->{add_delay}   || $DELAY_PER_ACTION;
        $max_delay        = $values->{i}->{delay_limit} || $DELAY_LIMIT;

        if ($reader_weight == 0) {
            $max_delay        = 72 * 3600;
            $base_delay       = 12 * 3600;
            $delay_per_action = 3  * 3600;
        } elsif ($reader_weight < 100) {
            $max_delay        = 24 * 3600;
            $base_delay       = 3  * 3600;
            $delay_per_action = 1  * 3600;
        }
    } else {
        $values      ||= {};
        $values->{f} ||= {};

        $base_delay       = $values->{f}->{delay_time}  || $BASE_DELAY;
        $delay_per_action = $values->{f}->{add_delay}   || $DELAY_PER_ACTION;
        $max_delay        = $values->{f}->{delay_limit} || $DELAY_LIMIT;

        if ($reader_weight < 100) {
            $base_delay       = 3 * 3600;
            $delay_per_action = 1 * 3600;
        }
    }

    ## delay for a job
    my $actions_in_q = LJ::FriendQueue->count($fromu);
    my $delay        = (1 + $actions_in_q) * $delay_per_action + $base_delay; # sec
    my $funcname     = "LJ::Worker::HandleUserFriendingActions";

    ## After each user's activities (friend/defriend) we increase the delay.
    ## If the delay exceeded the allowed level (DELAY_LIMIT) than flush all records
    ## and add info about it to log.
    if ($delay >= $max_delay) {
        $funcname = "LJ::Worker::FlushUserFriendingActions";
        $delay    = 0; # flush right now ))
    }

    my $time = time();
    my $job  = TheSchwartz::Job->new(
        funcname  => $funcname,
        arg       => [$fromu->userid, $time],
        run_after => $time + $delay,
    );

    if (my $sclient = LJ::theschwartz()) {
        $sclient->insert_jobs($job);

        my $jobid = $job->jobid; ## defined aftere insert_jobs

        LJ::FriendQueue->push($fromu, $tou,
            action   => $action,
            etime    => $time,
            jobid    => $jobid,
        );
    }
}

1;
