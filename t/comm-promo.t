#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
use vars qw(%maint);

require 'ljlib.pl';
require "paylib.pl";

use LJ::Test qw(temp_user temp_comm memcache_stress);

use Class::Autouse qw(
                      LJ::CommPromo
                      );

local $LJ::DISABLED{comm_promo} = 0;
local $LJ::__T_FORCE_SHOULD_PROMOTE_COMMUNITY = 1;
local $LJ::__T_FORCE_SHOULD_DISPLAY_COMMUNITY = 1;

my %made_friends = ();    # comm_u id => ct friends

my $new_user = sub {
    my $comm_u = temp_comm();

    # what friends should they have?
    for(1..rand(51)) {
        my $u = temp_user();
        LJ::add_friend($u, $comm_u);

        $made_friends{$comm_u->{userid}}++;
    }

    return $comm_u;
};

# require ljmaint handler so we can call it directly
require "$ENV{LJHOME}/bin/maint/comm_promo_list.pl";

# set a small block size for testing
$LJ::T_BLOCK_SIZE = 10;

foreach my $size (qw(5 15 25)) {
    my @temp_u = map { $new_user->() } 1..$size;

    # run maint handler
    $maint{comm_promo_list}->();

    # now check its output
    my $dbh = LJ::get_db_writer();

    # need to keep track of:
    my $total_rows       = 0; # total rows found in table
    my $watcher_ct_dirty = 0;
    my $watcher_wt_dirty = 0;

    # there will be users in the list that we did not create above, which will
    # affect the total... just select that from the DB using a ridiculous
    # join which is only okay in test-land.. ahhh, so simple.
    my $comm_ct = $dbh->selectrow_array
        ("SELECT COUNT(fr.userid) FROM comm_promo_list cpl, friends fr " .
         "WHERE cpl.journalid=fr.friendid");

    my $bind = join(",", map { "?" } @temp_u);
    my $sth = $dbh->prepare("SELECT journalid, r_start, r_end FROM comm_promo_list WHERE journalid IN ($bind)");
    $sth->execute(map { $_->{userid} } @temp_u);

    while (my ($uid, $start, $end) = $sth->fetchrow_array) {
        ok($made_friends{$uid}, "create user has entry in comm_promo_list");

        $total_rows++;
        my $weight = $end - $start;
        is($weight, POSIX::ceil($made_friends{$uid} / $comm_ct * $LJ::MAX_32BIT_SIGNED),
           "Got the correct weight");
    }
}
