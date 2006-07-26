#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use Carp;

$SIG{__DIE__} = sub { Carp::croak( @_ ) };

use LJ::Jabber::Presence;

use LJ::Test qw(temp_user);

my $u = temp_user();

checkres( $u, 0 );

my $one = {
    u => $u,
    resource => "Resource",
    cluster => "obj",
    client => "a client",
    presence => "<xml><data>",
};

my $two = {
    u => $u,
    resource => "Another Resource",
    cluster => "bobj",
    client => "another client",
    presence => "<more><xml>",
};

add( $one );
load( $one );

add( $two );
load( $two );
load( $one );

del( $one );
del( $two );

add( $one );
add( $two );

del_all();

add( $one );
load( $one );

add( $two );
load( $one );
load( $two );

delobj( $two );
delobj( $one );

add( $two );
add( $one );

delobj_all( $one );

my %presence;

sub add {
    my $args = shift;
    my $obj = LJ::Jabber::Presence->create( %$args );

    $presence{$args->{resource}} = 1;

    ok( $obj, "Object create" );
    checkattrs( $obj, $args );
    checkres( $u, scalar( keys %presence ) );

    return $obj;
}

sub load {
    my $args = shift;
    my $obj = LJ::Jabber::Presence->new( $u, $args->{resource} );

    ok( $obj, "Object load" );
    checkattrs( $obj, $args );
    checkres( $u, scalar( keys %presence ) );

    return $obj;
}

sub del {
    my $args = shift;
    LJ::Jabber::Presence->delete( $u->id, $args->{resource} );

    delete $presence{$args->{resource}};

    checkres( $u, scalar( keys %presence ) );
}

sub delobj {
    my $args = shift;
    my $obj = load( $args );

    delete $presence{$args->{resource}};
    $obj->delete;

    checkres( $u, scalar( keys %presence ) );
}

sub del_all {
    LJ::Jabber::Presence->delete_all( $u->id );

    %presence = ();

    checkres( $u, 0 );
}

sub delobj_all {
    my $args = shift;
    my $obj = load( $args );

    %presence = ();
    $obj->delete_all;

    checkres( $u, 0 );
}

sub checkattrs {
    my $obj = shift;
    my $check = shift;
    is( $obj->u, $check->{u}, "User matches" );
    is( $obj->resource, $check->{resource}, "Resource matches" );
    is( $obj->cluster, $check->{cluster}, "cluster matches" );
    is( $obj->client, $check->{client}, "client matches" );
    is( $obj->presence, $check->{presence}, "presence data matches" );
}

sub checkres {
    my $uid = shift;
    my $correct = shift;

    my $resources = LJ::Jabber::Presence->get_resources( $u->id );
    is( scalar(keys(%$resources)),$correct, "$correct Resources found for user" );
}
