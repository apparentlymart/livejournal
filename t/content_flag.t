# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::ContentFlag;
use LJ::Test;

my $u = temp_user();
my $u2 = temp_user();

my @flags;

my $entry = $u->t_post_fake_entry();
my $flag = LJ::ContentFlag->flag(item => $entry, reporter => $u2, journal => $u, cat => LJ::ContentFlag::ADULT);
ok($flag, "flagged entry");
push @flags, $flag;

ok($flag->flagid, "got flag id");

is($flag->status, LJ::ContentFlag::NEW, "flag is new");
is($flag->catid, LJ::ContentFlag::ADULT, "flag cat");
is($flag->modtime, undef, "no modtime");

my $time = time();
$flag->set_status(LJ::ContentFlag::OPEN);
is($flag->status, LJ::ContentFlag::OPEN, "status change");
ok(($flag->modtime - $time) < 2, "modtime");

my $flagid = $flag->flagid;

my ($dbflag) = LJ::ContentFlag->load_by_flagid($flagid);
ok($dbflag, "got flag object loading by flagid");
is_deeply($dbflag, $flag, "loaded same flag from db");

$flag->set_status(LJ::ContentFlag::NEW);

my ($dbflag) = LJ::ContentFlag->load_by_flagid($flagid, lock => 1);
ok($dbflag, "load_outstanding");

my ($dbflag) = LJ::ContentFlag->load_by_flagid($flagid, lock => 1);
ok(! $dbflag, "didn't get locked flag");


END {
    $_->delete foreach @flags;
};
