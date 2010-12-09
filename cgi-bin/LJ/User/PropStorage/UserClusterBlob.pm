package LJ::User::PropStorage::UserClusterBlob;
use strict;
use warnings;

use base qw(LJ::User::PropStorage::DB);

sub use_memcache { 'blob' }

sub memcache_key {
    my ( $class, $u, $propname ) = @_;

    my $propinfo = LJ::get_prop( 'user', $propname );

    return 'uprop2:blob:' . $u->id . ':' . $propinfo->{'id'};
}

sub can_handle {
    my ( $class, $propname ) = @_;

    my $propinfo = LJ::get_prop( 'user', $propname );
    return 0 unless $propinfo;

    return 0 if $propinfo->{'datatype'} =~ /^bit/;

    return 0 if $propinfo->{'multihomed'};

    return 0 unless $propinfo->{'cldversion'};
    return 0 unless $propinfo->{'datatype'} eq 'blobchar';

    return 1;
}

sub get_props {
    my ( $class, $u, $props, $opts ) = @_;

    my $dbh = $opts->{'use_master'} ? LJ::get_cluster_master($u)
                                    : LJ::get_cluster_reader($u);

    Carp::croak 'cannot get a database handle for user #' . $u->userid
        unless $dbh;

    return $class->fetch_props_db( $u, $dbh, 'userpropblob', $props );
}

sub set_props {
    my ( $class, $u, $propmap, $opts ) = @_;

    my $dbh = LJ::get_cluster_master($u);

    Carp::croak 'cannot get a database handle for user #' . $u->userid
        unless $dbh;

    return $class->store_props_db( $u, $dbh, 'userpropblob', $propmap );
}

1;
