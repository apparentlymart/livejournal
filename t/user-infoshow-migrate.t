#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw(temp_user memcache_stress);

$LJ::DISABLED{infoshow_migrate} = 0;

sub new_temp_user {
    my $u = temp_user();
    ok(LJ::isu($u), 'temp user created');

    is($u->{'allow_infoshow'}, 'Y', 'allow_infoshow defaulted to Y');

    LJ::load_user_props ($u, 'opt_showlocation', 'opt_showbday');
    ok(! defined $u->{'opt_showbday'}, 'opt_showbday not set');
    ok(! defined $u->{'opt_showlocation'}, 'opt_showlocation not set');

    return $u;
}


sub run_tests {
    foreach my $getter (
            sub { $_[0]->prop('opt_showbday') },
            sub { $_[0]->prop('opt_showlocation') },
            sub { $_[0]->opt_showbday },
            sub { $_[0]->opt_showlocation } )
    {
        foreach my $mode (qw(default off)) {
            my $u = new_temp_user();
            if ($mode eq 'off') {
                my $uid = $u->{userid};
                LJ::update_user($u, { allow_infoshow => 'N' });
                is($u->{allow_infoshow}, 'N', 'allow_infoshow set to N');

                my $temp_var = $getter->($u);
                is($temp_var, 'N', "prop value after migration: 'N'");
                is($u->{'allow_infoshow'}, ' ', 'lazy migrate: allow_infoshow set to SPACE');
                is($u->{'opt_showbday'}, 'N', 'lazy_migrate: opt_showbday set to N');
                is($u->{'opt_showlocation'}, 'N', 'lazy_migrate: opt_showlocation set to N');
            } else {
                my $temp_var = $u->opt_showbday; #$getter->($u);
                ok(! defined $temp_var, "prop value after migration: not defined");
                is($u->{'allow_infoshow'}, ' ', 'lazy migrate: allow_infoshow set to SPACE');
                ok(! defined $u->{'opt_showbday'}, 'lazy_migrate: opt_showbday not set');
                ok(! defined $u->{'opt_showlocation'}, 'lazy_migrate: opt_showlocation not set');
            }
        }
    }

}

memcache_stress {
    run_tests;
}
