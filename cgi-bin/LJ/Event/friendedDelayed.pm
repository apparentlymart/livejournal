package LJ::Event::friendedDelayed;
use strict;
use LJ::FriendQueue;

use constant BASE_DELAY       => 1800;         # sec
use constant DELAY_PER_ACTION => 600;          # sec
use constant DELAY_LIMIT      => 24 * 60 * 60; # sec

sub send {
    my $class = shift;

    my $action = shift;
    my $tou   = shift;
    my $fromu = shift;

    die "Wrong action parameter: $action" 
        unless $action =~ /^add|del$/;

    ## 1. create TheSchwartz job
    ##  1.1. calculate delay
    ##  
    ## 2. add info to FriendQueue 

    ## delay values
    my $systemu = LJ::load_user('system');
    LJ::load_user_props($systemu, qw/sys_base_friending_notif_delay 
                                     sys_friending_notif_delay 
                                     sys_limit_friending_notif_delay
                                     /);
    my $base_delay       = $systemu->prop('sys_base_friending_notif_delay')  || BASE_DELAY;
    my $delay_per_action = $systemu->prop('sys_friending_notif_delay')       || DELAY_PER_ACTION;
    my $max_delay        = $systemu->prop('sys_limit_friending_notif_delay') || DELAY_LIMIT;

    ## delay for a job
    my $actions_in_q = LJ::FriendQueue->count($fromu->userid);
    my $delay = (1 + $actions_in_q) * DELAY_PER_ACTION + BASE_DELAY; # sec
    my $funcname = "LJ::Worker::HandleUserFriendingActions";

    ## After each user's activities (friend/defriend) we increase the delay.
    ## If the delay exceeded the allowed level (DELAY_LIMIT) than flush all records
    ## and add info about it to log.
    if ($delay >= DELAY_LIMIT){
        $funcname = "LJ::Worker::FlushUserFriendingActions";
        $delay = 0; # flush right now ))
    }

    ##
    my $time = time();
    my $job = TheSchwartz::Job->new(
                funcname  => $funcname,
                arg       => [$fromu->userid, $time],
                run_after => $time + $delay,
                ); 

    my $sclient = LJ::theschwartz();
    $sclient->insert_jobs($job);

    my $jobid = $job->jobid; ## defined aftere insert_jobs

    LJ::FriendQueue->push(
        userid   => $fromu->userid,
        friendid => $tou->userid,
        action   => $action,
        etime    => $time,
        jobid    => $jobid,
        );

}

1;
