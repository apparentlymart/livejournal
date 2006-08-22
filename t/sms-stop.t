#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
no warnings 'redefine';
use LJ::Test qw (temp_user memcache_stress);
use Class::Autouse qw (
                       LJ::SMS::Message
                       LJ::SMS::MessageHandler
                       );
use Carp qw (croak);

my $lastmsg = '';

# trap message sending
$LJ::_T_SMS_SEND = sub {
    my $msg = shift;
    $lastmsg = $msg->body_text;
};

sub run_tests {
    my $u = temp_user();

    test_stop($u, $_) foreach (qw (stop end cancel unsubscribe quit), 'stop all');
}

sub test_stop {
    my $u = shift;
    my $msg = shift;

    my $sms_num = '+1';
    $sms_num .= int(rand(10)) foreach (1..10);
    $u->set_sms_number($sms_num, verified => 'Y');

    # reset user to normal active state
    $u->set_prop('sms_enabled', 'active');
    $u->set_prop('sms_yes_means', '');

    # have user send the stop message
    $u->t_receive_sms($msg);

    # now we should be asked to confirm
    like($lastmsg, qr/Are you sure you want to disable/i, "Got confirmation request");

    # reply with "yes"
    $u->t_receive_sms('yes');

    # user's SMS should now be disabled
    is($u->prop('sms_enabled'), "inactive", "sms_enabled now deactivated");
    is($u->prop('sms_yes_means'), '', "yes_means got cleared");

    # make sure they don't get messages anymore
    eval { $u->send_sms_text('test'); };
    unlike($lastmsg, qr/test/, "User no longer receives messages");

    # check that their number got reset
    ok(! $u->sms_number, "MSISDN cleared");

    ok(! $u->prop('sms_carrier'), "Carrier reset");
}


run_tests();
