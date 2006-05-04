# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use FindBin qw($Bin);
use LJ::Test qw(memcache_stress);

my $sysid = LJ::load_user("system")->{userid};
ok($sysid, "have a systemid");

memcache_stress(sub {
    LJ::start_request();
    is_empty();

    my $u = LJ::load_user("system");
    ok($u, "Have system user");
    die unless $u;

    my $u2 = LJ::load_userid($u->{userid});
    is($u, $u2, "whether loading by name or userid, \$u objects are singletons");

    my $bogus_bday = 9999999;
    $u2->{bdate} = $bogus_bday;

    is($u->{bdate}, $bogus_bday, "setting bdate to bogus");

    # this forced load will use the same memory address as our other $u of
    # the same id
    my $uf = LJ::load_userid($u->{userid}, "force");
    is($u, $uf, "forced userid load is u2");
    isnt($u2->{bday}, $bogus_bday, "our u2 bday is no longer bogus");

    my $uf2 = LJ::load_user("system", "force");
    is($uf2, $uf, "forced system");

    my $name = "My name is " . rand();
    LJ::update_user($u, { name => $name });
    is($u->{name}, $name, "name changed");
});


sub is_empty {
    is(scalar keys %LJ::REQ_CACHE_USER_NAME, 0, "reqcache for users is empty");
    is(scalar keys %LJ::REQ_CACHE_USER_ID, 0,   "reqcache for userids is empty");
}

sub run_tests {
    my $up;
    LJ::start_request();
    is_empty();
    my $u = LJ::load_user("system");
    ok($u, "Have system user");
    die unless $u;

    my $u2 = LJ::load_userid($u->{userid});
    is($u, $u2, "whether loading by name or userid, \$u objects are singletons");
}
