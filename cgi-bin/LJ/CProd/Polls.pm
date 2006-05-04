package LJ::CProd::Polls;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 unless LJ::get_cap($u, "makepoll");
    my $dbr = LJ::get_db_reader()
        or return 0;
    my $used_polls = $dbr->selectrow_array("SELECT pollid FROM poll WHERE posterid=?",
                                           undef, $u->{userid});
    return $used_polls ? 0 : 1;
}

1;
