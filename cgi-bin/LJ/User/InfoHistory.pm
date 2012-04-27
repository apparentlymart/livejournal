package LJ::User::InfoHistory;
use strict;
use warnings;

use LJ::User::InfoHistoryRecord;

sub add {
    my ( $class, $u, $what, $oldvalue, $other ) = @_;

    my $dbh = LJ::get_db_writer();
    local $dbh->{'RaiseError'} = 1;

    $dbh->do(
        'INSERT INTO infohistory ' .
        'SET userid=?, what=?, timechange=NOW(), oldvalue=?, other=?',
        undef,
        $u->userid, $what, $oldvalue, $other,
    );

    $LJ::REQ_GLOBAL{'infohistory_cache'} ||= {};
    delete $LJ::REQ_GLOBAL{'infohistory_cache'}->{ $u->userid };

}

sub get {
    my ( $class, $u, $what ) = @_;

    $LJ::REQ_GLOBAL{'infohistory_cache'} ||= {};
    unless ( exists $LJ::REQ_GLOBAL{'infohistory_cache'}->{ $u->userid } ) {
        my $dbr = LJ::get_db_reader();
        local $dbr->{'RaiseError'} = 1;

        my $rows = $dbr->selectall_arrayref(
            'SELECT * FROM infohistory WHERE userid=? ORDER BY timechange',
            { 'Slice' => {} },
            $u->userid,
        );

        $LJ::REQ_GLOBAL{'infohistory_cache'}->{ $u->userid } =
            [ map { LJ::User::InfoHistoryRecord->new($_) } @$rows ];
    }

    my $records = $LJ::REQ_GLOBAL{'infohistory_cache'}->{ $u->userid };
    return $records unless $what;

    if ( ref $what eq 'ARRAY' ) {
        my %acceptable_what = map { $_ => 1 } @$what;
        return [ grep { $acceptable_what{ $_->what } } @$records;
    } else {
        return [ grep { $_->what eq $what } @$records ];
    }
}

sub clear {
    my ( $class, $u ) = @_;

    my $dbh = LJ::get_db_writer();
    local $dbh->{'RaiseError'} = 1;

    $dbh->do( 'DELETE FROM infohistory WHERE userid=?', undef, $u->userid );

    $LJ::REQ_GLOBAL{'infohistory_cache'} ||= {};
    $LJ::REQ_GLOBAL{'infohistory_cache'}->{ $u->userid } = [];
}

1;
