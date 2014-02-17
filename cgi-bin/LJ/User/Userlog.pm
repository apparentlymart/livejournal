package LJ::User::Userlog;
use strict;
use warnings;

use LJ::User::UserlogRecord;

# opts: action, limit
# returns an arrayref of LJ::User::UserlogRecord
sub get_records {
    my ( $class, $u, %opts ) = @_;

    my $limit = int( $opts{'limit'} || 10_000 );
    my $begin = int( $opts{'begin'} || 0      );

    my $dbr = LJ::get_cluster_reader($u);
    my $rows;

    my $time_filter = '';
    if ( $opts{time_begin} && $opts{time_end} ) {
        my $time_begin = LJ::TimeUtil->mysqldate_to_time($opts{time_begin});
        my $time_end = LJ::TimeUtil->mysqldate_to_time($opts{time_end});
        $time_filter = sprintf("AND logtime > %s AND logtime < %s ", $time_begin, $time_end );
    }

    my $actions = $opts{'actions'};
    if ( my $action = $opts{'action'} ) {
        $actions = [$action];
    }
    @$actions = grep {$_} @$actions;
    if (@$actions) {
        my $sql_in = join( ',', ('?') x @$actions );
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? AND action IN ($sql_in) $time_filter" .
            "ORDER BY logtime DESC LIMIT $begin, $limit",
            { 'Slice' => {} }, $u->userid, @$actions,
        );
    } else {
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? $time_filter" .
            "ORDER BY logtime DESC LIMIT $begin, $limit",
            { 'Slice' => {} }, $u->userid,
        );
    }

    my @records = map { LJ::User::UserlogRecord->new(%$_) } @$rows;

    # hack: make account_create the last record (pretend that is's always the
    # one with the least timestamp)
    my ( @ret, @account_create_records );
    while ( my $record = shift @records ) {
        if ( $record->action eq 'account_create' ) {
            push @account_create_records, $record;
        } else {
            push @ret, $record;
        }
    }
    push @ret, @account_create_records;
    return \@ret;
}

sub get_records_count {
    my ($u, $actions) = @_;

    my $dbr = LJ::get_cluster_reader($u);

    my $count;
    if ( (ref $actions eq 'ARRAY') && (@$actions) ) {
        my $sql_in = join( ',', ('?') x @$actions );
        $count = $dbr->selectrow_array(
            "SELECT COUNT(*) FROM userlog WHERE userid=? AND action IN ($sql_in)",
            undef,
            $u->userid,
            @$actions
        );
    } else {
        $count = $dbr->selectrow_array('SELECT COUNT(*) FROM userlog WHERE userid=?', undef, $u->userid);
    }

    return $count;
}



1;
