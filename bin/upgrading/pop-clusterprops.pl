#!/usr/bin/perl
#
# This script converts from dversion 3 to dversion 4,
# which makes most userprops clustered
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $fromver = shift;
die "Usage: pop-clusterprops.pl <fromdversion>\n\t(where fromdversion is one of: 3)\n"
    unless $fromver == 3;

my $dbh = LJ::get_db_writer();

my $todo = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion=$fromver");
my $done = 0;
unless ($todo) {
    print "Nothing to convert.\n";
    exit 0;
}

sub get_some {
    my @list;
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion=$fromver LIMIT 200");
    $sth->execute;
    push @list, $_ while $_ = $sth->fetchrow_hashref;
    @list;
}

my $tover = $fromver + 1;
print "Converting $todo users from data version $fromver to $tover...\n";

my @props;
my $sth = $dbh->prepare("SELECT upropid FROM userproplist WHERE cldversion=?");
$sth->execute($tover);
push @props, $_ while $_ = $sth->fetchrow_array;
my $in = join(',', @props);
die "No values?" unless $in;

my $start = time();
while (my @list = get_some()) {
    LJ::start_request();
    foreach my $u (@list) {
        my $dbcm = LJ::get_cluster_master($u);
        next unless $dbcm;
        
        my %set;
        foreach my $table (qw(userprop userproplite)) {
            $sth = $dbh->prepare("SELECT upropid, value FROM $table WHERE userid=? AND upropid IN ($in)");
            $sth->execute($u->{'userid'});
            while (my ($id, $v) = $sth->fetchrow_array) {
                $set{$id} = $v;
            }
        }
        if (%set) {
            my $sql = "REPLACE INTO userproplite2 VALUES " . join(',', map {
                "($u->{'userid'},$_," . $dbh->quote($set{$_}) . ")" } keys %set);
            $dbcm->do($sql);
            if ($dbcm->err) {
                die "Error: " . $dbcm->errstr . "\n\n(Do you need to --runsql on your clusters first?)\n";
            }
            $dbh->do("DELETE FROM userprop WHERE userid=$u->{'userid'} AND upropid IN ($in)");
            $dbh->do("DELETE FROM userproplite WHERE userid=$u->{'userid'} AND upropid IN ($in)");
        }
        $dbh->do("UPDATE user SET dversion=$tover WHERE userid=$u->{'userid'} AND dversion=$fromver");
        $done++;
    }

    my $perc = $done/$todo;
    my $elapsed = time() - $start;
    my $total_time = $elapsed / $perc;
    my $min_remain = int(($total_time - $elapsed) / 60);
    printf "%d/%d complete (%.02f%%) minutes_remain=%d\n", $done, $todo, ($perc*100), $min_remain;
}
