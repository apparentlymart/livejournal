#!/usr/bin/perl
#

$maint{'clean_caches'} = sub 
{
    my $dbh = LJ::get_dbh("master");

    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");
    
    print "-I- Cleaning diresearchres.\n";
    my $pfx = $LJ::DIR_DB ? "$LJ::DIR_DB." : "";
    $dbh->do("DELETE FROM ${pfx}dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");

    ## clean the recent_* tables now (3 week cache on the slave dbs)
    return unless ($LJ::USE_RECENT_TABLES);

    my $sth;
    my $maxid;

    print "-I- Cleaning recent_logtext.\n";    
    $sth = $dbh->prepare("SELECT itemid FROM log WHERE logtime > DATE_SUB(NOW(), INTERVAL 21 DAY) LIMIT 1");
    $sth->execute;
    ($maxid) = $sth->fetchrow_array;
    
    ## only do cleaning if there's cleaning to be done:
    if ($maxid) {
	print "-I-   Cleaning all recent_logtext with itemids < $maxid\n";
	my $rows;
	do
	{
	    my $sth = $dbh->prepare("DELETE FROM recent_logtext WHERE itemid < $maxid LIMIT 500");
	    $sth->execute;
	    $rows = $sth->rows;
	    print "-I-    - deleted $rows rows\n";
	    sleep 1;
	} while ($rows);
    }

    print "-I- Cleaning recent_talktext.\n";    
    $sth = $dbh->prepare("SELECT talkid FROM talk WHERE datepost > DATE_SUB(NOW(), INTERVAL 21 DAY) LIMIT 1");
    $sth->execute;
    ($maxid) = $sth->fetchrow_array;
    
    ## only do cleaning if there's cleaning to be done:
    if ($maxid) {
	print "-I-   Cleaning all recent_talktext with talkids < $maxid\n";
	my $rows;
	do
	{
	    my $sth = $dbh->prepare("DELETE FROM recent_talktext WHERE talkid < $maxid LIMIT 500");
	    $sth->execute;
	    $rows = $sth->rows;
	    print "-I-    - deleted $rows rows\n";
	    sleep 1;
	} while ($rows);
    }


};

1;
