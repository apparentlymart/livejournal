# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

# some simple testing here. basically just make sure the has_subscription works right.

test_subscription(sub {
    my ($u1, $u2) = @_;
    my (@foundsubs, $subsc1, $subsc2, $res);

    # no params
    {
        eval { $u1->has_subscription() };
        like($@, qr/no parameters/i, "Bogus has_subscription call");
    }

    # invalid params
    {
        eval { $u1->has_subscription(ooga_booga => 123) };
        like($@, qr/invalid parameters/i, "Bogus has_subscription call");
    }

    # subscribe $u1 to all posts on $u2
    {
        $subsc1 = $u1->subscribe(
                                event   => "JournalNewComment",
                                method  => "SMS",
                                journal => $u2,
                                );
        ok($subsc1, "Made subscription");
    }

    # see if we can find this subscription
    {
        @foundsubs = $u1->has_subscription(
                                          event   => "JournalNewComment",
                                          method  => "SMS",
                                          journal => $u2,
                                          );
        is((scalar @foundsubs), 1, "Found one subscription");
    }

    # look for bogus subscriptions
    {
        @foundsubs = $u1->has_subscription(
                                          event   => "JournalNewComment",
                                          method  => "SMS",
                                          journal => $u1,
                                          );
        ok(!(scalar @foundsubs), "Couldn't find bogus subscription");
        @foundsubs = $u1->has_subscription(
                                          event   => "JournalNewEntry",
                                          method  => "SMS",
                                          journal => $u2,
                                          );
        ok(!(scalar @foundsubs), "Couldn't find bogus subscription");
        @foundsubs = $u1->has_subscription(
                                          event   => "JournalNewComment",
                                          method  => "Email",
                                          journal => $u2,
                                          );
        ok(!(scalar @foundsubs), "Couldn't find bogus subscription");
    }

    # look for more general matches
    {
        @foundsubs = $u1->has_subscription(
                                           method  => "SMS",
                                           );
        is((scalar @foundsubs), 1, "Found subscription");
        @foundsubs = $u1->has_subscription(
                                           event   => "JournalNewComment",
                                           );
        is((scalar @foundsubs), 1, "Found subscription");
        @foundsubs = $u1->has_subscription(
                                           journal => $u2,
                                           );
        is((scalar @foundsubs), 1, "Found subscription");
    }

    # add another subscription and do more searching
    {
        $subsc2 = $u1->subscribe(
                                 event    => "Befriended",
                                 method   => "SMS",
                                 journal  => $u2,
                                 arg1     => 10,
                                 );
        ok($subsc2, "Subscribed");

        # search for second subscription
        @foundsubs = $u1->has_subscription(
                                          event   => "Befriended",
                                          method  => "SMS",
                                          journal => $u2,
                                           arg1   => 10,
                                          );
        is((scalar @foundsubs), 1, "Found one new subscription");
    }

    # test filtering
    {
        @foundsubs = $u1->has_subscription(
                                           method  => "SMS",
                                           );
        is((scalar @foundsubs), 2, "Found two subscriptions");

        @foundsubs = $u1->has_subscription(
                                           event   => "JournalNewComment",
                                           );
        is((scalar @foundsubs), 1, "Found one subscription");

        @foundsubs = $u1->has_subscription(
                                           event   => "Befriended",
                                           );
        is((scalar @foundsubs), 1, "Found one subscription");

        @foundsubs = $u1->has_subscription(
                                           arg1    => 10,
                                           );
        is((scalar @foundsubs), 1, "Found one subscription");

        @foundsubs = $u1->has_subscription(
                                           journal => $u2,
                                           );
        is((scalar @foundsubs), 2, "Found two subscriptions");
    }

    # delete subscription and make sure we can't still find it
    {
        $subsc1->delete;
        @foundsubs = $u1->has_subscription(
                                          event   => "JournalNewComment",
                                          method  => "SMS",
                                          journal => $u2,
                                          );
        is((scalar @foundsubs), 0, "Didn't find subscription after deleting");
    }

    # delete subscription and make sure we can't still find it
    {
        $subsc2->delete;
        @foundsubs = $u1->has_subscription(
                                          event   => "Befriended",
                                          method  => "SMS",
                                          journal => $u2,
                                          );
        ok(!(scalar @foundsubs), "Didn't find subscription after deleting");
    }

    # test search params
    {
        my $subsc3 = $u1->subscribe(
                                    event     => "Befriended",
                                    method    => "SMS",
                                    journalid => $u2->{userid},
                                    );
        ok($subsc3, "Made subscription");
        ok(LJ::u_equals($subsc3->journal, $u2), "Subscribed to correct journal");
        $subsc3->delete;

        my $etypeid = LJ::Event::Befriended->etypeid;
        ok($etypeid, "Found etypeid for LJ::Event::Befriended");
        my $subsc4 = $u1->subscribe(
                                    etypeid   => $etypeid,
                                    method    => "SMS",
                                    journal   => $u2,
                                    );
        ok($subsc4, "Made subscription");
        is($subsc4->etypeid, $etypeid, "Subscribed to correct journal");
        $subsc4->delete;
    }
});

sub test_subscription {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    $u1->set_sms_number(12345);
    $u2->set_sms_number(67890);
    LJ::add_friend($u1, $u2); # make u1 friend u2
    $cv->($u1, $u2);
}
