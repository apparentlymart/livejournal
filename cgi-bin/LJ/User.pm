#
# LiveJournal user object
#
# 2004-07-21: we're transition from $u hashrefs to $u objects, currently
#             backed by hashrefs, to ease migration.  in the future,
#             more methods from ljlib.pl and other places will move here,
#             and the representation of a $u object will change to 'fields'.
#             at present, the motivation to moving to $u objects is to do
#             all database access for a given user through his/her $u object
#             so the queries can be tagged for use by the star replication
#             daemon.

use strict;

package LJ::User;
use Carp;

sub readonly {
    my $u = shift;
    return LJ::get_cap($u, "readonly");
}

# returns self (the $u object which can be used for $u->do) if
# user is writable, else 0
sub writer {
    my $u = shift;
    return $u if $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return 0;
}

# get an $sth from the writer
sub prepare {
    my $u = shift;
    croak "Database handle unavailable"
        unless $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return $u->{'_dbcm'}->prepare(@_);
}

# $u->do("UPDATE foo SET key=?", undef, $val);
sub do {
    my $u = shift;
    my $query = shift;

    my $uid = $u->{userid}+0
        or croak "Database update called on null user object";

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    $query =~ s!^(\s*\w+\s+)!$1/* uid=$uid */ !;

    my $rv = $dbcm->do($query, @_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub err {
    my $u = shift;
    return $u->{_dberr};
}

sub errstr {
    my $u = shift;
    return $u->{_dberrstr};
}

# <LJFUNC>
# name: LJ::User::dudata_set
# class: logging
# des: Record or delete disk usage data for a journal
# args: u, area, areaid, bytes
# area: One character: "L" for log, "T" for talk, "B" for bio, "P" for pic.
# areaid: Unique ID within $area, or '0' if area has no ids (like bio)
# bytes: Number of bytes item takes up.  Or 0 to delete record.
# returns: 1.
# </LJFUNC>
sub dudata_set {
    my ($u, $area, $areaid, $bytes) = @_;
    $bytes += 0; $areaid += 0;
    if ($bytes) {
        $u->do("REPLACE INTO dudata (userid, area, areaid, bytes) ".
               "VALUES (?, ?, $areaid, $bytes)", undef,
               $u->{userid}, $area);
    } else {
        $u->do("DELETE FROM dudata WHERE userid=? AND ".
               "area=? AND areaid=$areaid", undef,
               $u->{userid}, $area);
    }
    return 1;
}

1;
