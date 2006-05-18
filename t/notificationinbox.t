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
                      );

my $u = temp_user();
ok($u, "Got temp user");

sub run_tests {
    my $q;
    my $rv;
    my @notifications;
    my $qid;
    my $evt;
    my $qitem;

    # try bogus constructors
    {
        # Inbox
        $rv = eval { LJ::NotificationInbox->new() };
        like($@, qr/invalid args/i, "Invalid args");

        $rv = eval { LJ::NotificationInbox->new({bogus => "ugly"}) };
        like($@, qr/invalid user/i, "Invalid user");

        # Item
        $rv = eval { LJ::NotificationItem->new() };
        like($@, qr/no inbox/i, "no inbox");

        $rv = eval { LJ::NotificationItem->new(inbox => 1) };
        like($@, qr/no queue id/i, "no queue id");

        $rv = eval { LJ::NotificationItem->new(inbox => 1, qid => 2, state => 3)};
        like($@, qr/no event/i, "no event");

        $rv = eval { LJ::NotificationItem->new(inbox => 1, qid => 2, state => 3, event => 4, blah => 5) };
        like($@, qr/invalid options/i, "invalid options");
    }

    # create a queue
    {
        $q = LJ::NotificationInbox->new($u);
        ok($q, "Got queue");
    }

    # create an event to enqueue and enqueue it
    {
        $evt = LJ::Event::ForTest->new($u, 42, 666);
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
        is_deeply($qitem->event, $evt, "Event is same");
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

package LJ::Event::ForTest;
use base 'LJ::Event';
sub new {
    my ($class, $u, $arg1, $arg2) = @_;
    my $self = $class->SUPER::new($u, $arg1, $arg2);

    return $self;
}


1;
