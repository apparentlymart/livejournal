#!/usr/bin/perl

# Tests LJ::NotificationInbox and LJ::NotificationItem

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

use Class::Autouse qw(
                      LJ::NotificationInbox
                      LJ::NotificationItem
                      LJ::Event
                      LJ::Event::Befriended
                      );

my $u = temp_user();
my $u2 = temp_user();
ok($u && $u2, "Got temp users");

sub run_tests {
    my $q;
    my $rv;
    my @notifications;
    my $qid;
    my $evt;
    my $qitem;

    # create a queue
    {
        $q = $u->notification_inbox;
        ok($q, "Got queue");
    }

    # create an event to enqueue and enqueue it
    {
        $evt = LJ::Event::Befriended->new($u, $u2);
        ok($evt, "Made event");
        # enqueue this event
        $qid = $q->enqueue(event => $evt);
        ok($qid, "Enqueued event");
    }

    # check the queued events and make sure we get what we put in
    {
        @notifications = $q->items;
        ok(@notifications, "Got notifications list");
        ok((scalar @notifications) == 1, "Got one item");
        $qitem = $notifications[0];
        ok($qitem, "Item exists");
        is($qitem->event->etypeid, $evt->etypeid, "Event is same");
    }

    # test states
    {
        # default is unread
        ok($qitem->unread, "Item is marked as unread");
        ok(! $qitem->read, "Item is not marked as read");

        # mark it read
        $qitem->mark_read;
        ok($qitem->read, "Item is marked as read");
        ok(! $qitem->unread, "Item is not marked as unread");

        # mark it unread
        $qitem->mark_unread;
        ok($qitem->unread, "Item is marked as unread");
        ok(! $qitem->read, "Item is not marked as read");
    }

    # delete this from the queue
    {
        $rv = $qitem->delete;
        ok($rv, "Deleting from queue");
        # we shouldn't have any items left in the queue now
        @notifications = $q->items;
        ok(!@notifications, "No items left in queue");
    }
}

memcache_stress {
    run_tests();
};

1;
