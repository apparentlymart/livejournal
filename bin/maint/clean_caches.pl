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

    ## clean the recent_* tables now (3 week cache on the slave dbs)
    return unless ($LJ::USE_RECENT_TABLES);

    my $maxid;

    print "-I- Cleaning recent_logtext.\n";    
    $sth = $dbh->prepare("SELECT itemid FROM log WHERE logtime > DATE_SUB(NOW(), INTERVAL $LJ::RECENT_DAYS DAY) LIMIT 1");
    $sth->execute;
    ($maxid) = $sth->fetchrow_array;
    
    ## only do cleaning if there's cleaning to be done:
    if ($maxid) {
        print "-I-   Cleaning all recent_logtext with itemids < $maxid\n";
        my $rows;
        do
        {
            $sth = $dbh->prepare("DELETE FROM recent_logtext WHERE itemid < $maxid LIMIT 500");
            $sth->execute;
            $rows = $sth->rows;
            print "-I-    - deleted $rows rows\n";
            sleep 1;
        } while ($rows);
    }

    print "-I- Cleaning recent_talktext.\n";    
    $sth = $dbh->prepare("SELECT talkid FROM talk WHERE datepost > DATE_SUB(NOW(), INTERVAL $LJ::RECENT_DAYS DAY) LIMIT 1");
    $sth->execute;
    ($maxid) = $sth->fetchrow_array;
    
    ## only do cleaning if there's cleaning to be done:
    if ($maxid) {
        print "-I-   Cleaning all recent_talktext with talkids < $maxid\n";
        my $rows;
        do
        {
            $sth = $dbh->prepare("DELETE FROM recent_talktext WHERE talkid < $maxid LIMIT 500");
            $sth->execute;
            $rows = $sth->rows;
            print "-I-    - deleted $rows rows\n";
            sleep 1;
        } while ($rows);
    }


};

1;
