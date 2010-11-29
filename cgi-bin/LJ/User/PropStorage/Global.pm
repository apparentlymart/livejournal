package LJ::User::PropStorage::Global;
use strict;
use warnings;

use base qw( LJ::User::PropStorage::DB );

sub memcache_key {
    my ( $class, $u ) = @_;

    return 'uprop2:global:' . $u->id;
}

sub can_handle {
    my ( $class, $propname ) = @_;

    my $propinfo = LJ::get_prop( 'user', $propname );
    return 0 unless $propinfo;

    return 0 if $propinfo->{'datatype'} =~ /^bit/;

    return 0 if $propinfo->{'multihomed'};
    return 0 if $propinfo->{'indexed'};

    return 0 if $propinfo->{'cldversion'};
    return 0 if $propinfo->{'datatype'} eq 'blobchar';

    return 1;
}

sub get_props {
    my ( $class, $u, $props, $opts ) = @_;

    my $dbh = $opts->{'use_master'} ? LJ::get_db_writer()
                                    : LJ::get_db_reader();

    Carp::croak 'cannot get a database handle for global cluster'
        unless $dbh;

    return $class->fetch_props_db( $u, $dbh, 'userproplite', $props );
}

sub set_props {
    my ( $class, $u, $propmap, $opts ) = @_;

    my $dbh = LJ::get_db_writer();

    Carp::croak 'cannot get a database handle for global cluster'
        unless $dbh;

    return $class->store_props_db( $u, $dbh, 'userproplite', $propmap );
}

1;
