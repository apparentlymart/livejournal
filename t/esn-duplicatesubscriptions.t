
# -*-perl-*-

@LJ::EVENT_TYPES = ('LJ::Event::ForTest1', 'LJ::Event::ForTest2');

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

my $u1 = temp_user();
my $u2 = temp_user();

$u1->set_sms_number(12345);

my %got_sms = ();   # userid -> received sms
local $LJ::_T_SMS_SEND = sub {
    my $sms = shift;
    my $rcpt = $sms->to_u or die "No destination user";
    $got_sms{$rcpt->{userid}}++;
};

my $proc_events = sub {
    %got_sms = ();
    LJ::Event->process_fired_events;
};

my $got_notified = sub {
    my $u = shift;
    $proc_events->();
    return $got_sms{$u->{userid}};
};


sub run_tests {
    # subscribe $u1 to receive all new comments on an entry by $u1,
    # then subscribe $u1 to receive all new comments on a thread under
    # that entry. Then, make sure $u1 only receives one notification
    # for each new comment on that thread instead of two.

    # post an entry on $u2
    ok($u1 && $u2, "Got users");
    my $entry = $u2->t_post_fake_entry;
    ok($entry, "Posted fake entry");

    # subscribe $u1 to new comments on this entry
    my $subscr1 = $u1->subscribe(
                                 journal => $u2,
                                 arg1    => $entry->ditemid,
                                 method  => "SMS",
                                 event   => "JournalNewComment",
                                 );
    ok($subscr1, "Subscribed u1 to new comments on entry");

    # make a comment and make sure $u1 gets notified
    my $c_parent = $entry->t_enter_comment;
    ok($c_parent, "Posted comment");

    my $notifycount = $got_notified->($u1);
    ok($notifycount == 1, "Got notified once");

    # subscribe u1 to new comments on this thread
    my $subscr2 = $u1->subscribe(
                                 journal => $u2,
                                 arg1    => $entry->ditemid,
                                 arg2    => $c_parent->jtalkid,
                                 method  => "SMS",
                                 event   => "JournalNewComment",
                                 );
    ok($subscr2, "Subscribed u1 to new comments on thread");

    # post a reply to the thread and make sure $u1 only got notified once
    $c_parent->t_reply;

    $notifycount = $got_notified->($u1);
    ok($notifycount == 1, "Got notified only once");

    $subscr1->delete;
    $subscr2->delete;
}

run_tests();


1;

