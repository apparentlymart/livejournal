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

    if ($LJ::USE_RECENT_TABLES)
    {
	print "-I- Cleaning recent_logtext.\n";
	my $sth;
	
	# find the first itemid that's within the last 3 weeks. 
	# NOTE: no ORDER BY looks wrong, but with it mysql will do a filesort which is slow.
	#       besides, it's not necessary since mysql returns the lowest anyway (at least it seems to)

	$sth = $dbh->prepare("SELECT itemid FROM log WHERE logtime > DATE_SUB(NOW(), INTERVAL 21 DAY) LIMIT 1");
	$sth->execute;
	my ($maxid) = $sth->fetchrow_array;

	## only do cleaning if there's cleaning to be done:
	if ($maxid) {
	    print "-I-   Cleaning all recent_logtext itemids < $maxid\n";
	    my $rows;
	    do
	    {
		my $sth = $dbh->prepare("DELETE FROM recent_logtext WHERE itemid < $maxid LIMIT 200");
		$sth->execute;
		$rows = $sth->rows;
		print "-I-    - deleted $rows rows\n";
		sleep 1;
	    } while ($rows);
	}
    }

};

1;
