#!/usr/bin/perl
#

package ljsupport;

## pass $id of zero or blank to get all categories
sub load_spcats
{
    my ($dbh, $hashref, $id) = @_;
    $id += 0;
    my $where = $id ? "WHERE spcatid=$id" : "";
    my $sth = $dbh->prepare("SELECT * FROM supportcat $where");
    $sth->execute;
    $hashref->{$_->{'spcatid'}} = $_ while ($_ = $sth->fetchrow_hashref);
}

sub calc_points
{
    my ($base, $secs) = @_;
    $secs = int($secs / (3600*6));
    my $total = ($base + $secs);
    if ($total > 10) { $total = 10; }
    $total ||= 1;
    return $total;
}

1;
