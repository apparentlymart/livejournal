#!/usr/bin/perl
#

$maint{'clean_caches'} = sub 
{
    &connect_db();    
    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");
    
    print "-I- Cleaning diresearchres.\n";
    my $pfx = $LJ::DIR_DB ? "$LJ::DIR_DB." : "";
    $dbh->do("DELETE FROM ${pfx}dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");
};

1;
