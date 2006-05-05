#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

use Class::Autouse qw(
                      LJ::NotificationInbox
                      LJ::Event
                      );

my $u = temp_user();
ok($u, "Got temp user");

sub run_tests {
    my $q;
    my $rv;
    my $events;
    my $qid;
    my $evt;

    # try bogus constructors
    {
        $rv = eval { LJ::NotificationInbox->new() };
        like($@, qr/invalid args/i, "Invalid args");

        $rv = eval { LJ::NotificationInbox->new({bogus => "ugly"}) };
        like($@, qr/invalid user/i, "Invalid user");
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
        $events = $q->notifications;
        ok($events, "Got notifications list");
        ok((scalar keys %$events) == 1, "Got one notification");
        is_deeply((values %$events), $evt, "Event is same");
    }

    # delete this from the queue
    {
        $rv = $q->delete_from_queue($qid);
        ok($rv, "Deleting from queue");
        # we shouldn't have any items left in the queue now
        $events = $q->notifications;
        ok(!%$events, "No items left in queue");
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
