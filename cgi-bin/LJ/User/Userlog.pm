package LJ::User::Userlog;
use strict;
use warnings;

use LJ::User::UserlogRecord;

# opts: action, limit
# returns an arrayref of LJ::User::UserlogRecord
sub get_records {
    my ( $class, $u, %opts ) = @_;

    my $limit = int( $opts{'limit'} || 10_000 );

    my $dbr = LJ::get_cluster_reader($u);
    my $rows;

    my $actions = $opts{'actions'};
    if ( my $action = $opts{'action'} ) {
        $actions = [$action];
    }

    if ($actions) {
        my $sql_in = join( ',', ('?') x @$actions );
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? AND action IN ($sql_in) " .
            "ORDER BY logtime DESC LIMIT $limit",
            { 'Slice' => {} }, $u->userid, @$actions,
        );
    } else {
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? " .
            "ORDER BY logtime DESC LIMIT $limit",
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

1;
