#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

use Class::Autouse qw(
                      LJ::NotificationQueue
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
        $rv = eval { LJ::NotificationQueue->new() };
        like($@, qr/invalid args/i, "Invalid args");

        $rv = eval { LJ::NotificationQueue->new({bogus => "ugly"}) };
        like($@, qr/invalid user/i, "Invalid user");
    }

    # create a queue
    {
        $q = LJ::NotificationQueue->new($u);
        ok($q, "Got queue");
    }

    # create an event to enqueue
    {
        $evt = LJ::Event::ForTest->new($u, 69, 42, 666);
        ok($evt, "Made event");
        # enqueue this event
        $qid = $q->enqueue(event => $evt);
        ok($qid, "Enqueued event");
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
    my ($class, $u, $journalid, $arg1, $arg2) = @_;
    my $self = $class->SUPER::new($u, $arg1, $arg2);

    $self->{journalid} = $journalid;

    return $self;
}


1;
