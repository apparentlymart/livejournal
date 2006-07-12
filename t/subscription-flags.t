# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Subscription;
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);

run_tests();

sub run_tests {
    my $u = temp_user();

    # create a subscription
    my $subscr = LJ::Subscription->create(
                                          $u,
                                          event => 'JournalNewEntry',
                                          journalid => 0,
                                          method => 'Inbox',
                                          );

    ok($subscr, "Got subscription");

    # test flag setter/accessors
    {
        my $flags = $subscr->flags;
        is($flags, 0, "No flags set");

        # set inactive flag
        $subscr->deactivate;
        ok(! $subscr->active, "Deactivated");

        # make sure inactive flag is set
        $flags = $subscr->flags;
        is($flags, LJ::Subscription::INACTIVE, "Inactive flag set");

        # clear inactive flag
        $subscr->activate;

        # make sure inactive flag is unset
        $flags = $subscr->flags;
        is($flags, 0, "Inactive flag unset");

        # set a bunch of flags and clear one
        $subscr->set_flag(1);
        $subscr->set_flag(2);
        $subscr->set_flag(4);
        $subscr->set_flag(8);
        $subscr->clear_flag(4);

        is($subscr->flags, 11, "Cleared one flag ok");
    }
}
