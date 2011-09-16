package LJ::User::PropStorage::DB;
use strict;
use warnings;

use base qw( LJ::User::PropStorage );

sub can_handle { 0 }
sub use_memcache { 'lite' }

sub fetch_props_db {
    my ( $class, $u, $dbh, $table, $props ) = @_;

    my $userid = int $u->userid;

    LJ::load_props('user');

    my @propids;

    foreach my $k (@$props) {
        my $propinfo = LJ::get_prop('user', $k);
        my $propid   = $propinfo->{'id'};

        push @propids, $propid;
    }

    LJ::load_props('user') unless defined LJ::MemCache::get('CACHE_PROPID');
    my %propid_map = %{ LJ::MemCache::get('CACHE_PROPID')->{'user'} };

    my %ret = map { $_ => undef } @$props;
    my $sql;

    if ( my $propids_in = join(',', @propids) ) {
        $sql = qq{
            SELECT upropid, value
            FROM $table
            WHERE userid=? AND upropid IN ($propids_in)
        };
    }
    else {
        # well, it seems that they didn't pass us any props, so
        # let's use a somewhat different SQL query to load everything
        # from the given table
        $sql = qq{
            SELECT upropid, value
            FROM $table
            WHERE userid=?
        };
    }

    my $res = $dbh->selectall_arrayref($sql, { 'Slice' => {} }, $userid);

    foreach my $row (@$res) {
        my $propname = $propid_map{ $row->{'upropid'} }->{'name'};

        # filter out spurious data; we need this because multihomed
        # userprops used to be stored on user clusters as well, but we
        # don't store them on user clusters anymore, and the data
        # that still sits there got outdated.
        next unless $class->get_handler($propname) eq $class;

        $ret{$propname} = $row->{'value'};
    }

    return \%ret;
}

sub store_props_db {
    my ( $class, $u, $dbh, $table, $propmap ) = @_;

    my $userid = int $u->userid;

    my ( @values_sql, @subst, @propid_delete );
    foreach my $k (keys %$propmap) {
        my $propinfo = LJ::get_prop('user', $k);
        my $propid   = $propinfo->{'id'};

        unless ( defined $propmap->{$k} && $propmap->{$k} ) {
            push @propid_delete, $propid;
            next;
        }

        push @values_sql, '(?, ?, ?)';
        push @subst, $userid, $propid, $propmap->{$k};
    }

    if ( my $values_sql = join(',', @values_sql) ) {
        $dbh->do(qq{
            REPLACE INTO $table
            (userid, upropid, value)
            VALUES $values_sql
        }, undef, @subst);
    }

    if ( my $props_delete_in = join(',', @propid_delete) ) {
        $dbh->do(qq{
            DELETE FROM $table
            WHERE userid=? AND upropid IN ($props_delete_in)
        }, undef, $userid);
    }
}

1;
