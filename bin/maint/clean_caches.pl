#!/usr/bin/perl
#

$maint{'clean_caches'} = sub 
{
    my $dbh = LJ::get_dbh("master");
    my $sth;

    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning faquses.\n";
    $dbh->do("DELETE FROM faquses WHERE dateview < DATE_SUB(NOW(), INTERVAL 7 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");

    print "-I- Cleaning diresearchres.\n";
    # need insert before delete so master logs delete and slaves actually do it
    $dbh->do("INSERT INTO dirsearchres2 VALUES (MD5(NOW()), DATE_SUB(NOW(), INTERVAL 31 MINUTE), '')");
    $dbh->do("DELETE FROM dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");

    print "-I- Cleaning meme.\n";
    do {
        $sth = $dbh->prepare("DELETE FROM meme WHERE ts < DATE_SUB(NOW(), INTERVAL 7 DAY) LIMIT 250");
        $sth->execute;
        if ($dbh->err) { print $dbh->errstr; }
        print "    deleted ", $sth->rows, "\n";
    } while ($sth->rows && ! $sth->err);
};

1;
