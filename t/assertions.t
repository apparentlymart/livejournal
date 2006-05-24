# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

ok(LJ::assert_is("foo", "foo"));
ok(! eval { LJ::assert_is("foo", "bar") });

my $u = LJ::load_user("system");
ok($u->selfassert);
{
    local $u->{userid} = 9999;
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    ok(! eval { $u->selfassert });
}
ok($u->selfassert);
{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::require_master(sub { LJ::load_userid($u->{userid}) });
    };
    like($@, qr/Assertion failure/);
}

{
    local $u->{user} = "systemNOT";
    eval {
        my $u2 = LJ::load_userid($u->{userid});
    };
    like($@, qr/Assertion failure/);
}

{
    local $u->{userid} = 5555;
    eval {
        my $u2 = LJ::load_user("system");
    };
    like($@, qr/Assertion failure/);
}



