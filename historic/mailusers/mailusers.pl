#!/usr/bin/perl

require "/home/lj/cgi-bin/ljlib.pl";

$newsnum = $ARGV[0];

unless ($newsnum =~ /^\d+$/) {
    die "Need argv[0] = newsnum!\n";
}

$base = "";
while (<STDIN>) {
    $base .= $_;
}

#$where = "u.allow_getljnews='Y' AND u.status='A' AND u.statusvis='V'";

$where = "u.paidfeatures IN ('early', 'off') AND u.status='A' AND u.statusvis='V' AND u.timeupdate > DATE_SUB(NOW(), INTERVAL 14 DAY)";

#$where = "u.status='A' AND u.statusvis='V' AND u.country='US' and u.state IN ('OR', 'WA', 'ID') AND u.timeupdate > DATE_SUB(NOW(), INTERVAL 21 DAY)";

#$where = "u.userid=1";
#$where = "u.status='A' AND u.timeupdate > DATE_SUB(NOW(), INTERVAL 7 DAY)";
#$where = "u.status='A' AND (u.allow_getljnews='Y' OR u.lastn_style NOT IN (1, 2, 3, 4, 5, 20, 6) OR u.friends_style NOT IN (1, 2, 3, 4, 5, 20, 6))";

my $ct = 0;
&connect_db;
$sth = $dbh->prepare("SELECT u.user FROM user u WHERE $where");
$sth->execute;
if ($dbh->err) { print $dbh->errstr; }

my @users;
push @users, $_->{'user'} while ($_ = $sth->fetchrow_hashref);

my ($count) = scalar(@users);
print "Count: $count\n";

foreach my $user (@users)
{
    $ct++;
    print "$ct/$count: ";   

    my $quser = $dbh->quote($user);
    $sth = $dbh->prepare("SELECT COUNT(*) AS 'sent' FROM news_sent WHERE user=$quser AND newsnum=$newsnum");
    $sth->execute;
    my ($sent) = $sth->fetchrow_array;
    if ($sent) {
	print "$user: skipping.\n";
	next;
    } else {
	$sth = $dbh->prepare("SELECT userid, user, email, name, timeupdate FROM user WHERE user=$quser");
	$sth->execute;
	$c = $sth->fetchrow_hashref;
    }

#    my $aa = &register_authaction($c->{'userid'}, "nonews");
#    next unless $aa;
#    $c->{'authid'} = $aa->{'aaid'}; 
#    $c->{'authcode'} = $aa->{'authcode'}; 

    $msg = $base;
    $msg =~ s/\[(\w+?)\]/$c->{$1}/g;
    open (MAIL, "|$SENDMAIL");
    print MAIL $msg;
    close MAIL;

    ### log the spam
    my $quser = $dbh->quote($c->{'user'});
    my $qemail = $dbh->quote($c->{'email'});
    $dbh->do("INSERT INTO news_sent (newsnum, user, datesent, email) VALUES ($newsnum, $quser, NOW(), $qemail)");
    if ($dbh->err) { die $dbh->errstr; }

    print "mailed $user ($c->{'email'})...\n";
}

print "Done.\n";
