#!/usr/bin/perl
#

use strict;
use vars qw($dbh %maint);

$maint{'genstats'} = sub
{
    my @which = @_;

    unless (@which) { @which = qw(usage users countries 
                                  states gender clients
                                  pop_interests meme pop_faq); }
    my %do = map { $_, 1, } @which;
    
    my $dbh = LJ::get_db_writer(); 
    my $dbr = LJ::get_db_reader();
    my $sth;

    my %account;
    my %userinfo;
    my %age;
    my %newbyday;
    my %gender;
    my %stateus;
    my %country;
    my %pop_interests;
    my ($nowtime, $time, $nowdate);

    my %to_pop;

    if ($do{'pop_faq'}) {
        $sth = $dbr->prepare("SELECT faqid, COUNT(*) FROM faquses WHERE ".
                             "faqid<>0 GROUP BY 1 ORDER BY 2 DESC LIMIT 50");
        $sth->execute;
        my $d = $to_pop{'popfaq'} = {};
        while (my ($id, $count) = $sth->fetchrow_array) {
            $d->{$id} = $count;
        }
    }

    if ($do{'meme'}) {
        $sth = $dbr->prepare("SELECT url, count(*) FROM meme GROUP BY 1 ORDER BY 2 DESC LIMIT 100");
        $sth->execute;
        my $memedata = $to_pop{'popmeme'} = {};
        while (my ($url, $count) = $sth->fetchrow_array) {
            $memedata->{$url} = $count;
        }
    }

    if ($do{'usage'})
    {
        print "-I- Getting usage by day in last month...\n";
        $sth = $dbr->prepare("SELECT UNIX_TIMESTAMP(), DATE_FORMAT(NOW(), '%Y-%m-%d')");
        $sth->execute;
        ($nowtime, $nowdate) = $sth->fetchrow_array;
        
        print "Date is: $nowdate\n";
        
        for (my $days_back = 30; $days_back > 0; $days_back--) {
            print "  going back $days_back days... ";
            $time = $nowtime - 86400*$days_back;
            my ($year, $month, $day) = (localtime($time))[5, 4, 3];
            $year += 1900;
            $month += 1;
            my $date = sprintf("%04d-%02d-%02d", $year, $month, $day);
            my $qdate = $dbr->quote($date);
            my $exist = $dbr->selectrow_array("SELECT COUNT(*) FROM stats WHERE statcat='postsbyday' AND statkey=$qdate");
            if ($exist) {
                print "exists.\n";
                next;
            } 

            my $total = 0;
            # livejournal.log was removed (clustered). Removing query.
            foreach my $c (@LJ::CLUSTERS) {
                my $dbcr = LJ::get_cluster_reader($c);
                $total += $dbcr->selectrow_array("SELECT COUNT(*) FROM log2 WHERE year=$year ".
                                                 "AND month=$month AND day=$day");
            }
            
            print "$date = $total entries\n";
            $dbh->do("REPLACE INTO stats (statcat, statkey, statval) ".
                     "VALUES ('postsbyday', $qdate, $total)");
        }
    }

    if ($do{'users'})
    {
        $to_pop{'userinfo'} = \%userinfo;
        $to_pop{'account'} = \%account;
        $to_pop{'age'} = \%age;
        $to_pop{'newbyday'} = \%newbyday;

        print "-I- Getting user stats...\n";

        my $now = time();
        my $usertotal = $dbr->selectrow_array("SELECT MAX(userid) FROM user");
        my $pagesize = 1000;
        my $pages = int($usertotal / $pagesize) + (($usertotal % $pagesize) ? 1 : 0);
        
        for (my $page=0; $page < $pages; $page++)
        {
            my ($loid, $hiid) = ($page*$pagesize+1, ($page+1)*$pagesize);
            print "  getting records $loid-$hiid...\n";
            $sth = $dbr->prepare("SELECT DATE_FORMAT(uu.timecreate, '%Y-%m-%d') AS 'datereg', u.user, u.caps, FLOOR((TO_DAYS(NOW())-TO_DAYS(u.bdate))/365.25) AS 'age', UNIX_TIMESTAMP(uu.timeupdate) AS 'timeupdate', u.status, u.allow_getljnews FROM user u, userusage uu WHERE u.userid=uu.userid AND u.userid BETWEEN $loid AND $hiid");
            $sth->execute;
            while (my $rec = $sth->fetchrow_hashref)
            {
                my $co = $rec->{'country'};
                if ($co) {
                    $country{$co}++; 
                    if ($co eq "US" && $rec->{'state'}) {
                        $stateus{$rec->{'state'}}++;
                    }
                }
                
                my $capnameshort = LJ::name_caps_short($rec->{'caps'});
                $account{$capnameshort}++;
                
                unless ($rec->{'datereg'} eq $nowdate) {
                    $newbyday{$rec->{'datereg'}}++;
                }
                
                if ($rec->{'age'} > 4 && $rec->{'age'} < 110) {
                    $age{$rec->{'age'}}++;
                }
                
                $userinfo{'total'}++;
                $time = $rec->{'timeupdate'};
                $userinfo{'updated'}++ if ($time);
                $userinfo{'updated_last30'}++ if ($time > $now-60*60*24*30);
                $userinfo{'updated_last7'}++ if ($time > $now-60*60*24*7);
                $userinfo{'updated_last1'}++ if ($time > $now-60*60*24*1);
                
                if ($rec->{'status'} eq "A")
                {
                    for (qw(allow_getljnews))
                    {
                        $userinfo{$_}++ if ($rec->{$_} eq "Y");
                    }
                }
                
            }
        }
    }
    # All of the below uses clustered tables.  Make one large loop
    # to prevent having 4 smaller loops.
    foreach my $c (@LJ::CLUSTERS) {
    	die "Can't get cluster $c db handle."
            unless my $dbcr = LJ::get_cluster_reader($c);
    	print "-I- Getting userprop stats on cluster $c.\n";
	
	my $upc = LJ::get_prop("user", "country");
    	die "Can't find country userprop.  Database populated?\n" unless $upc;

    	if ($do{'countries'})
    	{
        	$to_pop{'country'} = \%country;

        	print "-I- Countries.\n";
        	$sth = $dbcr->prepare("SELECT value, COUNT(*) AS 'count' FROM userproplite2 ".
                             "WHERE upropid=$upc->{'id'} AND value<>'' GROUP BY 1 ORDER BY 2");
        	$sth->execute;
        	while ($_ = $sth->fetchrow_hashref) {
            		$country{$_->{'value'}} += $_->{'count'};
		}
    	}

    	if ($do{'states'}) 
    	{
        	$to_pop{'stateus'} = \%stateus;

        	my $ups = LJ::get_prop("user", "state");
        	die "Can't find state userprop.  Database populated?\n" unless $ups;

        	print "-I- US States.\n";
        	$sth = $dbcr->prepare("SELECT ua.value, COUNT(*) AS 'count' FROM userproplite2 ua, userproplite2 ub WHERE ua.userid=ub.userid AND ua.upropid=$ups->{'id'} and ub.upropid=$upc->{'id'} and ub.value='US' AND ub.value<>'' GROUP BY 1 ORDER BY 2");
        	$sth->execute;
        	while ($_ = $sth->fetchrow_hashref) {
            		$stateus{$_->{'value'}} += $_->{'count'};
        	}
    	}

    	if ($do{'gender'}) 
    	{
        	$to_pop{'gender'} = \%gender;

        	my $upg = LJ::get_prop("user", "gender");
        	die "Can't find gender userprop.  Database populated?\n" unless $upg;

        	print "-I- Gender.\n";
        	$sth = $dbcr->prepare("SELECT value, COUNT(*) AS 'count' ".
                             "FROM userproplite2 WHERE upropid=$upg->{'id'} GROUP BY 1");
        	$sth->execute;
        	while ($_ = $sth->fetchrow_hashref) {
            		$gender{$_->{'value'}} += $_->{'count'};
        	}
    	}
    }
    
    if ($do{'pop_interests'})
    {
        $to_pop{'pop_interests'} = \%pop_interests;

        print "-I- Interests.\n";
        $sth = $dbr->prepare("SELECT interest, intcount FROM interests WHERE intcount>2 ORDER BY intcount DESC, interest ASC LIMIT 400");
        $sth->execute;
        while (my ($int, $count) = $sth->fetchrow_array) {
            $pop_interests{$int} = $count;
        }
    }
    
    foreach my $cat (keys %to_pop)
    {
        print "  dumping $cat stats\n";
        my $qcat = $dbh->quote($cat);
        $dbh->do("DELETE FROM stats WHERE statcat=$qcat");
        if ($dbh->err) { die $dbh->errstr; }
        foreach (sort keys %{$to_pop{$cat}}) {
            my $qkey = $dbh->quote($_);
            my $qval = $to_pop{$cat}->{$_}+0;
            $dbh->do("REPLACE INTO stats (statcat, statkey, statval) VALUES ($qcat, $qkey, $qval)");
            if ($dbh->err) { die $dbh->errstr; }
        }
    }

    #### client usage stats

    if ($do{'clients'})
    {
        print "-I- Clients.\n";
        $sth = $dbr->prepare("SELECT c.client, COUNT(*) AS 'count' FROM clients c, clientusage cu ".
                             "WHERE c.clientid=cu.clientid AND cu.lastlogin > ".
                             "DATE_SUB(NOW(), INTERVAL 30 DAY) GROUP BY 1 ORDER BY 2");
        $sth->execute;

        $dbh->do("DELETE FROM stats WHERE statcat='client'");
        while ($_ = $sth->fetchrow_hashref) {
            my $qkey = $dbh->quote($_->{'client'});
            my $qval = $_->{'count'}+0;
            $dbh->do("REPLACE INTO stats (statcat, statkey, statval) VALUES ('client', $qkey, $qval)");
        }
    }

    #### dump to text file
    print "-I- Dumping to a text file.\n";

    $sth = $dbh->prepare("SELECT statcat, statkey, statval FROM stats ORDER BY 1, 2");
    $sth->execute;
    open (OUT, ">$LJ::HTDOCS/stats/stats.txt");
    while (@_ = $sth->fetchrow_array) {
        print OUT join("\t", @_), "\n";
    }
    close OUT;

    #### do stat box stuff
    print "-I- Preparing stat box overviews.\n";
    my %statbox;
    my $v;

    ## total users
    $sth = $dbh->prepare("SELECT statval FROM stats WHERE statcat='userinfo' AND statkey='total'");
    $sth->execute;
    ($v) = $sth->fetchrow_array;
    $statbox{'totusers'} = $v;
    
    ## how many posts yesterday
    $sth = $dbh->prepare("SELECT statval FROM stats WHERE statcat='postsbyday' ORDER BY statkey DESC LIMIT 1");
    $sth->execute;
    ($v) = $sth->fetchrow_array;
    $statbox{'postyester'} = $v;

    foreach my $k (keys %statbox) {
        my $qk = $dbh->quote($k);
        my $qv = $dbh->quote($statbox{$k});
        $dbh->do("REPLACE INTO stats (statcat, statkey, statval) VALUES ('statbox', $qk, $qv)");
    }

    print "-I- Done.\n";

};

$maint{'genstats_size'} = sub {
    my $dbh = LJ::get_dbh("master");
    return unless $dbh;

    print "-I- Finding total & active size.\n";
    my $period = 30;  # one month is considered active
    my $size = $dbh->selectrow_array("SELECT COUNT(*) FROM userusage");
    my $active = $dbh->selectrow_array("SELECT COUNT(*) FROM userusage WHERE ".
                                       "timecheck > DATE_SUB(NOW(), INTERVAL $period DAY) OR ".
                                       "timeupdate > DATE_SUB(NOW(), INTERVAL $period DAY) OR ".
                                       "timecreate > DATE_SUB(NOW(), INTERVAL $period DAY)");
    return unless $size && $active;
    $dbh->do("REPLACE INTO stats (statcat, statkey, statval) ".
             "VALUES ('size', 'accounts', ?), ('size', 'accounts_active', ?)",
             undef, $size, $active);
    print "-I- Done.\n";
};


$maint{'genstats_weekly'} = sub
{
    my $dbh = LJ::get_dbh("master");

    my ($sth);
    my %supportrank;

    print "-I- Support rank.\n";
    $sth = $dbh->prepare("SELECT u.userid, SUM(sp.points) AS 'points' FROM user u, supportpoints sp WHERE u.userid=sp.userid GROUP BY 1 ORDER BY 2 DESC");
    my $rank = 0;
    my $lastpoints = 0;
    my $buildup = 0;
    $sth->execute;
    {
        while ($_ = $sth->fetchrow_hashref) 
        {
            if ($lastpoints != $_->{'points'}) {
                $lastpoints = $_->{'points'};
                $rank += (1 + $buildup);
                $buildup = 0;
            } else {
                $buildup++;
            }
            $supportrank{$_->{'userid'}} = $rank;
        }
    }

    $dbh->do("DELETE FROM stats WHERE statcat='supportrank_prev'");
    $dbh->do("UPDATE stats SET statcat='supportrank_prev' WHERE statcat='supportrank'");

    my %to_pop = (
                  "supportrank" => \%supportrank,
                  );
    
    foreach my $cat (keys %to_pop)
    {
        print "  dumping $cat stats\n";
        my $qcat = $dbh->quote($cat);
        $dbh->do("DELETE FROM stats WHERE statcat=$qcat");
        if ($dbh->err) { die $dbh->errstr; }
        foreach (sort keys %{$to_pop{$cat}}) {
            my $qkey = $dbh->quote($_);
            my $qval = $to_pop{$cat}->{$_}+0;
            $dbh->do("REPLACE INTO stats (statcat, statkey, statval) VALUES ($qcat, $qkey, $qval)");
            if ($dbh->err) { die $dbh->errstr; }
        }
    }

};

$maint{'build_randomuserset'} = sub
{
    ## this sets up the randomuserset table daily (or whenever) that htdocs/random.bml uses to
    ## find a random user that is both 1) publicly listed in the directory, and 2) updated
    ## within the past 24 hours.

    ## note that if a user changes their privacy setting to not be in the database, it'll take
    ## up to 24 hours for them to be removed from the random.bml listing, but that's acceptable.

    my $dbh = LJ::get_dbh("master");

    print "-I- Building randomuserset.\n";
    $dbh->do("TRUNCATE TABLE randomuserset");
    $dbh->do("REPLACE INTO randomuserset (userid) SELECT uu.userid FROM userusage uu, user u WHERE u.userid=uu.userid AND u.allow_infoshow='Y' AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 1 DAY) LIMIT 5000");
    my $num = $dbh->selectrow_array("SELECT MAX(rid) FROM randomuserset");
    $dbh->do("REPLACE INTO stats (statcat, statkey, statval) VALUES ('userinfo', 'randomcount', $num)");
    print "-I- Done.\n";
};

$maint{'memeclean'} = sub
{
    my $dbh = LJ::get_dbh("master");
    my $sth;

    $sth = $dbh->prepare("SELECT statkey FROM stats WHERE statcat='popmeme'");
    $sth->execute;
    while (my $url = $sth->fetchrow_array)
    {
        my $copy = $url;
        LJ::run_hooks("canonicalize_url", \$copy);
        unless ($copy) {
            my $d = $dbh->quote($url);
            $dbh->do("DELETE FROM stats WHERE statcat='popmeme' AND statkey=$d");
            print "Deleting: $url\n";
        }
    }
    print "done.\n";
};

1;
