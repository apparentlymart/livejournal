#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Jabber::Presence;

use LJ::Test qw(temp_user);

my $u = temp_user();

checkres( $u, 0 );

my %pres_one = (
		u => $u,
		resource => "Resource",
		cluster => "obj",
		presence => "<xml><data>",
		);
{
    my $one = LJ::Jabber::Presence->create( %pres_one );

    ok( $one, "Object successfully created" );
    checkattrs( $one, \%pres_one );
    checkres( $u, 1 );
}

{
    my $reload_one = LJ::Jabber::Presence->new( $u, $pres_one{resource} );

    ok( $reload_one, "Object loaded" );
    checkattrs( $reload_one, \%pres_one );
    checkres( $u, 1 );
}

my %pres_two = (
		u => $u,
		resource => "Another Resource",
		cluster => "bobj",
		presence => "<more><xml>",
		);

{
    my $two = LJ::Jabber::Presence->create( %pres_two );
    
    ok( $two, "Second object created" );
    checkattrs( $two, \%pres_two );
    checkres( $u, 2 );   
}

{
    my $reload_two = LJ::Jabber::Presence->new( $u, $pres_two{resource} );

    ok( $reload_two, "Object loaded" );
    checkattrs( $reload_two, \%pres_two );
    checkres( $u, 2 );
}

{
    my $reload_one = LJ::Jabber::Presence->new( $u, $pres_one{resource} );

    ok( $reload_one, "Object loaded" );
    checkattrs( $reload_one, \%pres_one );
    checkres( $u, 2 );
}
sub checkattrs {
    my $obj = shift;
    my $check = shift;
    is( $obj->u, $check->{u}, "User matches" );
    is( $obj->resource, $check->{resource}, "Resource matches" );
    is( $obj->cluster, $check->{cluster}, "cluster matches" );
    is( $obj->presence, $check->{presence}, "presence data matches" );
}

sub checkres {
    my $uid = shift;
    my $correct = shift;

    my $resources = LJ::Jabber::Presence->get_resources( $u->id );
    is( scalar(keys(%$resources)),$correct, "$correct Resources found for user" );

}
