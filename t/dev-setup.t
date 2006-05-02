# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

if ($LJ::IS_DEV_SERVER) {
    plan tests => 5;
} else {
    plan skip_all => "not a developer machine";
    exit 0;
}

my $u = LJ::load_user("system");
ok($u);

ok(scalar @LJ::CLUSTERS >= 2, "have 2 or more clusters");
ok(scalar keys %LJ::DBINFO >= 3, "have 2 or more dbinfo config sections");

my %seen_db;
while (my ($n, $inf) = each %LJ::DBINFO) {
    if ($n eq "master") {
        ok(1, "have a master section");
        my $user_on_master = 0;
        foreach my $cid (@LJ::CLUSTERS) {
            $user_on_master = 1 if
                $inf->{role}{"cluster$cid"};
        }
        ok(!$user_on_master, "you don't have a cluster configured on a master");
    }
}

