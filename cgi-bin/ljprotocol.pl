#!/usr/bin/perl
#

require '/home/lj/cgi-bin/ljpoll.pl';
require '/home/lj/cgi-bin/ljconfig.pl';

package LJ;

sub do_request
{
    # get the request and response hash refs
    my ($dbh, $req, $res, $flags) = @_;

    # declare stuff
    my ($user, $userid, $lastitemid, $name, $paidfeatures, $correctpassword, $status, $statusvis, $track, $sth);

    # initialize some stuff
    %{$res} = ();                      # clear the given response hash
    $user = &trim(lc($req->{'user'}));
    my $quser = $dbh->quote($user);

    # check for an alive database connection
    unless ($dbh)
    {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Server error: cannot connect to database.";
        return;
    }

    # did they send a mode?
    unless ($req->{'mode'})
    {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No mode specified.";
        return;
    }
    
    unless ($user)
    {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No username sent.";
        return;
    }

    ### see if the server's under maintenance now
    if ($LJ::SERVER_DOWN) 
    {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = $LJ::SERVER_DOWN_MESSAGE;
        return;
    }

    # authenticate user
    unless ($flags->{'noauth'}) # && $req->{'mode'} ne "login")
    {
        $sth = $dbh->prepare("SELECT user, userid, lastitemid, journaltype, name, paidfeatures, password, status, statusvis, track FROM user WHERE user=$quser");
        $sth->execute;
        if ($dbh->err)
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Server database error: " . $dbh->errstr;
	  return;
        }
        ($user, $userid, $lastitemid, $journaltype, $name, $paidfeatures, $correctpassword, $status, $statusvis, $track) = $sth->fetchrow_array;

        if ($user eq "")
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "User error: Invalid Username";
	  return;
        }
        unless ($flags->{'nopassword'} || &valid_password($correctpassword, { 
	  "password" => $req->{'password'}, 
	  "hpassword" => $req->{'hpassword'}
        }))
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "User error: Invalid Password";
	  return;
        }
	if ($statusvis eq "S") {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Account error: this account has been suspended.  Contact tech support for more information.";
	}
	if ($statusvis eq "D") {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Account error: this account has been deleted.";
	}
    }
    
    ### even if noauth is on, we need the userid
    if ($userid == 0) 
    {
	if ($flags->{'userid'}) {
	    $userid = $flags->{'userid'};
	} else {
	    $sth = $dbh->prepare("SELECT userid FROM user WHERE user=$quser");
	    $sth->execute;
	    ($userid) = $sth->fetchrow_array;
	}
    }

    $userid += 0;

    ################################ AUTHENTICATED NOW ################################

    if ($req->{'mode'} eq "login" || 
	$req->{'mode'} eq "getfriendgroups" ||
	($req->{'mode'} eq "getfriends" && $req->{'includegroups'}))
    {
	$sth = $dbh->prepare("SELECT groupnum, groupname, sortorder, is_public FROM friendgroup WHERE userid=$userid");
	$sth->execute;
	my $maxnum = 0;
	while ($_ = $sth->fetchrow_hashref) {
	    my $num = $_->{'groupnum'};
	    $res->{"frgrp_${num}_name"} = $_->{'groupname'};
	    $res->{"frgrp_${num}_sortorder"} = $_->{'sortorder'};
	    if ($_->{'is_public'}) {
		$res->{"frgrp_${num}_public"} = 1;
	    }
	    if ($num > $maxnum) { $maxnum = $num; }
	}
	$res->{'frgrp_maxnum'} = $maxnum;

	if ($req->{'mode'} eq "getfriendgroups") {
	    $res->{'success'} = "OK";
	    return;
	}
	if ($user eq "test") {
	    sleep(2);
	}
    }

    if ($req->{'mode'} eq "login")
    {
        $res->{'success'} = "OK";
        $res->{'name'} = $name;
        if ($user eq "test") { 
	    $res->{'message'} = "Hello Test Account!"; 
	}
	if ($req->{'clientversion'} =~ /^Win32-MFC\/(1.2.[0123456])$/ ||
	    $req->{'clientversion'} =~ /^Win32-MFC\/(1.3.[01234])\b/)
	{
	    $res->{'message'} = "There's a significantly newer version of LiveJournal for Windows available.";
	}
	unless ($LJ::EVERYONE_VALID)
	{
	    if ($status eq "N") { $res->{'message'} = "You are currently not validated.  You may continue to use LiveJournal, but please validate your email address for continued use.  See the instructions that were mailed to you when you created your journal, or see $LJ::SITEROOT/support/ for more information."; }
	    if ($status eq "T") { $res->{'message'} = "You need to validate your new email address.  Your old one was good, but since you've changed it, you need to re-validate the new one.  Visit the support area for more information."; }
	}
	if ($status eq "B") { $res->{'message'} = "You are currently using a bad email address.  All mail we try to send you is bouncing.  We require a valid email address for continued use.  Visit the support area for more information."; }

	### report what shared journals this user may post in
	my $access_count = 0;
	my $sth = $dbh->prepare("SELECT u.user FROM user u, logaccess la WHERE la.ownerid=u.userid AND la.posterid=$userid ORDER BY u.user");
	$sth->execute;
	while ($_ = $sth->fetchrow_hashref) {
	    $access_count++;
	    $res->{"access_${access_count}"} = $_->{'user'};
	}
	if ($access_count) {
	    $res->{"access_count"} = $access_count;
	}

	### picture keywords
	if (defined $req->{"getpickws"}) 
	{
	    my $pickw_count = 0;
	    my $sth = $dbh->prepare("SELECT k.keyword FROM userpicmap m, keywords k WHERE m.userid=$userid AND m.kwid=k.kwid ORDER BY k.keyword");
	    $sth->execute;
	    while ($_ = $sth->fetchrow_array) {
		$pickw_count++;
		$res->{"pickw_${pickw_count}"} = $_;
	    }
	    if ($pickw_count) {
		$res->{"pickw_count"} = $pickw_count;
	    }
	}

	### report new moods that this client hasn't heard of, if they care
	if (defined $req->{"getmoods"}) {
	    my $mood_max = $req->{"getmoods"}+0;
	    my $mood_count = 0;
	    &load_moods($dbh);

	    if ($mood_max < $LJ::CACHED_MOOD_MAX) 
	    {
		for (my $id=$mood_max+1; $id <= $LJ::CACHED_MOOD_MAX; $id++)
		{
		    if (defined $LJ::CACHE_MOODS{$id}) {
			my $mood = $LJ::CACHE_MOODS{$id};
			$mood_count++;
			$res->{"mood_${mood_count}_id"} = $id;
			$res->{"mood_${mood_count}_name"} = $mood->{'name'};
		    }
		}
	    }
	    if ($mood_count) {
		$res->{"mood_count"} = $mood_count;
	    }
	}

	#### send web menus
	if ($req->{"getmenus"} == 1) {
	    my $menu = [
			{ 'text' => "Recent Entries",
			  'url' => "$LJ::SITEROOT/users/$user/", },
			{ 'text' => "Calendar View",
			  'url' => "$LJ::SITEROOT/users/$user/calendar", },
			{ 'text' => "Friends View",
			  'url' => "$LJ::SITEROOT/users/$user/friends", },
			{ 'text' => "-", },
			{ 'text' => "Your Profile",
			  'url' => "$LJ::SITEROOT/userinfo.bml?user=$user", },
			{ 'text' => "Your To-Do List",
			  'url' => "$LJ::SITEROOT/todo/?user=$user", },
			{ 'text' => "-", },
			{ 'text' => "Change Settings",
			  'sub' => [ { 'text' => "Personal Info",
				       'url' => "$LJ::SITEROOT/editinfo.bml", },
				     { 'text' => "Journal Settings",
				       'url' =>"$LJ::SITEROOT/modify.bml", }, ] },
			{ 'text' => "-", },
			{ 'text' => "Support", 
			  'url' => "$LJ::SITEROOT/support/", }
			];

	    unless ($paidfeatures eq "on" || $paidfeatures eq "paid") 
	    {
		push @$menu, { 'text' => 'Upgrade your account',
			       'url' => "$LJ::SITEROOT/paidaccounts/", };
	    }
	    
	    my $menu_num = 0;
	    &populate_web_menu($res, $menu, \$menu_num);

        }

	# tell the client it's a paid user so it can send the "ljfastserver" 
	# cookie and get access to the fast servers through the load balancer
	if ($paidfeatures eq "on" || $paidfeatures eq "paid") 
	{
	    $res->{'fastserver'} = "1";
	}
	
	#### update or add to logins table
	if (0) { 	#### FIXME: TEMP: this is disabled for now. (2001-03-01)
	    my $qclient = $dbh->quote($req->{'clientversion'});
	    $sth = $dbh->prepare("UPDATE logins SET lastlogin=NOW() WHERE user=$quser AND client=$qclient");
	    $sth->execute;
	    unless ($sth->rows) {
		$dbh->do("INSERT INTO logins (user, client, timelogin, lastlogin) VALUES ($quser, $qclient, NOW(), NOW())");
	    }
	}

        return;
    }
  
    ###
    ### MODE: editfriendgroups
    ### (rename, add, and delete friend groups)
    ###
    if ($req->{'mode'} eq "editfriendgroups")
    {
	my %delete_pass;
	my @passes = ($req, \%delete_pass);

	###
	## Keep track of what bits are already set, so we can know later whether to INSERT
	#  or UPDATE.

	my %bitset;
	$sth = $dbh->prepare("SELECT groupnum FROM friendgroup WHERE userid=$userid");
	$sth->execute;
	while (my ($bit) = $sth->fetchrow_array) {
	    $bitset{$bit} = 1;
	}

	foreach my $hash (@passes) 
	{
	    foreach (keys %{$hash})
	    {
		if (/^editfriend_groupmask_(\w+)$/) 
		{
		    my $friend = $1;
		    my $mask = $req->{"editfriend_groupmask_${friend}"}+0;
		    $mask |= 1;  # make sure bit 0 is on
		    my $qfriend = $dbh->quote($friend);

		    $sth = $dbh->prepare("SELECT userid FROM user WHERE user=$qfriend");
		    $sth->execute;
		    my ($friendid) = $sth->fetchrow_array;
		    if ($friendid) {
			$sth = $dbh->prepare("UPDATE friends SET groupmask=$mask WHERE userid=$userid AND friendid=$friendid");
			$sth->execute;
		    }
		} 
		elsif (/^efg_delete_(\d+)/)
		{
		    my $bit = $1;
		    next unless ($req->{"efg_delete_$bit"}); # test for true
		    next unless ($bit >=1 && $bit <= 30);
		    
		    # remove all friend's priviledges on that bit number?  No, client should do this.
		    
		    # remove all posts from allowing that group:
		    my @posts_to_clean = ();
		    $sth = $dbh->prepare("SELECT itemid FROM logsec WHERE ownerid=$userid AND allowmask & (1 << $bit)");
		    $sth->execute;
		    while (my ($id) = $sth->fetchrow_array) { push @posts_to_clean, $id; }
		    while (@posts_to_clean) {
			my @batch;
			if (scalar(@posts_to_clean) < 20) {
			    @batch = @posts_to_clean; 
			    @posts_to_clean = ();
			} else {
			    @batch = splice(@posts_to_clean, 0, 20); 
			}
			my $in = join(",", @batch);
			$dbh->do("UPDATE log SET allowmask=allowmask & ~(1 << $bit) WHERE itemid IN ($in) AND security='usemask'");
			$dbh->do("UPDATE logsec SET allowmask=allowmask & ~(1 << $bit) WHERE ownerid=$userid AND itemid IN ($in)");
		    }
		    
		    # remove the friend group
		    $sth = $dbh->prepare("DELETE FROM friendgroup WHERE userid=$userid AND groupnum=$bit");
		    $sth->execute;
		}
		elsif (/^efg_set_(\d+)_name/)
		{
		    my $bit = $1;
		    next unless ($bit >=1 && $bit <= 30);
		    my $name = $req->{"efg_set_${bit}_name"};
		    if ($name =~ /\S/) {
			my $qname = $dbh->quote($name);
			my $qsort = defined $req->{"efg_set_${bit}_sort"} ? 
			    ($req->{"efg_set_${bit}_sort"}+0) : 50;
			my $qpublic = $dbh->quote(defined $req->{"efg_set_${bit}_public"} ?
			    ($req->{"efg_set_${bit}_public"}+0) : 0);
			
			if ($bitset{$bit}) {
			    # and set it..
			    my $sets;
			    if (defined $req->{"efg_set_${bit}_public"}) {
				$sets .= ", is_public=$qpublic";
			    }
			    $sth = $dbh->prepare("UPDATE friendgroup SET groupname=$qname, sortorder=$qsort $sets WHERE userid=$userid AND groupnum=$bit");
			} else {
			    $sth = $dbh->prepare("INSERT INTO friendgroup (userid, groupnum, groupname, sortorder, is_public) VALUES ($userid, $bit, $qname, $qsort, $qpublic)");			    
			}
			$sth->execute;
		    } else {
			# delete the group if the group name is just whitespace
			$delete_pass{"efg_delete_$bit"} = 1;
		    }
		}
	    } # end foreach on keys
	} # end foreach on passes

        $res->{'success'} = "OK";
	return;
    }
    

    ###
    ### MODE: getdaycounts
    ### (find out how many journal entries appear on each day)
    ###
    if ($req->{'mode'} eq "getdaycounts")
    {
	### shared-journal support
	my $ownerid = $userid;
	if ($req->{'usejournal'}) {
            my $info = {};
	    if (&can_use_journal($dbh, $userid, $req->{'usejournal'}, $info)) {
		$ownerid = $info->{'ownerid'};
	    } else {
                $res->{'errmsg'} = $info->{'errmsg'};
		$res->{'success'} = "FAIL"; 
		return;
	    }
	}
	
        $sth = $dbh->prepare("SELECT year, month, day, COUNT(*) AS 'count' FROM log WHERE ownerid=$ownerid GROUP BY 1, 2, 3");
        $sth->execute;
        while ($_ = $sth->fetchrow_hashref)
        {
	    my $date = sprintf("%04d-%02d-%02d", $_->{'year'}, $_->{'month'}, $_->{'day'});
	    $res->{$date} = $_->{'count'};
        }
        $res->{'success'} = "OK";
	return; 
    }

    ###
    ### MODE: friendsof
    ### (who all lists you as a friend?)
    ###
    if ($req->{'mode'} eq "friendof" ||
	($req->{'mode'} eq "getfriends" && $req->{'includefriendof'}))
    {
        $sth = $dbh->prepare("SELECT u.user, u.journaltype, f.fgcolor, f.bgcolor FROM friends f, user u WHERE u.userid=f.userid AND f.friendid=$userid AND u.statusvis='V' ORDER BY user");
        $sth->execute;
        my @friendof;
        push @friendof, $_ while $_ = $sth->fetchrow_hashref;
        my $userin = join(", ", map { $dbh->quote($_->{'user'}) } @friendof);
        $sth = $dbh->prepare("SELECT user, name FROM user WHERE user IN ($userin)");
        $sth->execute;
        my %name;
        $name{$_->{'user'}} = $_->{'name'} while $_ = $sth->fetchrow_hashref;
        my $i=0;
        foreach (@friendof)
        {
	  $i++;
	  $res->{"friendof_${i}_user"} = $_->{'user'};
	  if ($_->{'journaltype'} eq "C") {
	      $res->{"friendof_${i}_type"} = "community";
	  }
	  $res->{"friendof_${i}_name"} = $name{$_->{'user'}};
	  $res->{"friendof_${i}_fg"} = $_->{'fgcolor'};
	  $res->{"friendof_${i}_bg"} = $_->{'bgcolor'};
        }
        $res->{'friendof_count'} = $i;
        $res->{'success'} = "OK";

	if ($req->{'mode'} eq "friendof") { return; }
    }

    ###
    ### MODE: getfriends
    ### (who are your friends?)
    ###
    if ($req->{'mode'} eq "getfriends")
    {
        $sth = $dbh->prepare("SELECT u.user AS 'friend', u.journaltype, f.fgcolor, f.bgcolor, f.groupmask FROM user u, friends f WHERE u.userid=f.friendid AND f.userid=$userid AND u.statusvis='V'");
        $sth->execute;
        my @friendof;
        push @friendof, $_ while $_ = $sth->fetchrow_hashref;
	@friendof = sort { $a->{'friend'} cmp $b->{'friend'} } @friendof;

        my $userin = join(", ", map { $dbh->quote($_->{'friend'}) } @friendof);
        $sth = $dbh->prepare("SELECT user, name FROM user WHERE user IN ($userin)");
        $sth->execute;
        my %name;
        $name{$_->{'user'}} = $_->{'name'} while $_ = $sth->fetchrow_hashref;
        my $i=0;
        foreach (@friendof)
        {
	  $i++;
	  $res->{"friend_${i}_user"} = $_->{'friend'};
	  $res->{"friend_${i}_name"} = $name{$_->{'friend'}};
	  $res->{"friend_${i}_fg"} = $_->{'fgcolor'};
	  $res->{"friend_${i}_bg"} = $_->{'bgcolor'};
	  if ($_->{'groupmask'} != 1) {
	      $res->{"friend_${i}_groupmask"} = $_->{'groupmask'};
	  }
	  if ($_->{'journaltype'} eq "C") {
	      $res->{"friend_${i}_type"} = "community";
	  }
        }
        $res->{'friend_count'} = $i;
        $res->{'success'} = "OK";
        return;
    }

    ####
    #### MODE: editfriends
    ####
    if ($req->{'mode'} eq "editfriends")
    {
	## first, figure out who the current friends are to save us work later
	my %curfriend;
        $sth = $dbh->prepare("SELECT u.user FROM user u, friends f WHERE u.userid=f.friendid AND f.userid=$userid");
        $sth->execute;
	while (my ($friend) = $sth->fetchrow_array) {
	    $curfriend{$friend} = 1;
	}

        # perform the deletions
        foreach (keys %{$req})
        {
	    if (/^editfriend_delete_(\w+)/) 
	    {
		my $qfriend = $dbh->quote(lc($1));
		my $friendid = LJ::get_userid($dbh, lc($1));

		## delete from friends table
		$sth = $dbh->prepare("DELETE FROM friends WHERE userid=$userid AND friendid=$friendid");
		$sth->execute;
	    }
        }
	
        my $error_flag = 0;
	my $friends_added = 0;
	
        # perform the adds
      ADDFRIEND:
        foreach (keys %{$req})
        {
	    if (/^editfriend_add_(\d+)_user/) 
	    {
		my $n = $1;
		my $name = lc($req->{"editfriend_add_${n}_user"});
		next ADDFRIEND unless ($name);
		my $fg = $req->{"editfriend_add_${n}_fg"} || "#000000";
		my $bg = $req->{"editfriend_add_${n}_bg"} || "#FFFFFF"; 
		if ($fg !~ /^\#[0-9A-F]{6,6}$/i || $bg !~ /^\#[0-9A-F]{6,6}$/i)
		{
		    $res->{'success'} = "FAIL";
		    $res->{'errmsg'} = "Client error: Invalid color values";
		    return;
		}
		my $qname = $dbh->quote($name);
		my $sth = $dbh->prepare("SELECT user, userid, name FROM user WHERE user=$qname");
		$sth->execute;
		my $row = $sth->fetchrow_hashref;
		unless ($row) {
		    $error_flag = 1;
		}
		else
		{
		    $friends_added++;
		    $res->{"friend_${friends_added}_user"} = $name;
		    $res->{"friend_${friends_added}_name"} = $row->{'name'};
		    my $qfg = $dbh->quote($fg);
		    my $qbg = $dbh->quote($bg);
		    
		    my $friendid = $row->{'userid'};

		    ### get the group mask if friend already exists, or default to 1 (bit 0 (friend bit) set)
		    $sth = $dbh->prepare("SELECT groupmask FROM friends WHERE userid=$userid AND friendid=$friendid");
		    $sth->execute;
		    my ($gmask) = $sth->fetchrow_array;
		    $gmask ||= 1;
		    
		    $sth = $dbh->prepare("REPLACE INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) VALUES ($userid, $friendid, $qfg, $qbg, $gmask)");
		    $sth->execute;

		    if ($dbh->err) {
			$res->{'success'} = "FAIL";
			$res->{'errmsg'} = "Database error [fr]: " . ($dbh->errstr);
			return;
		    }
		    $sth->finish;
		}
	    }  ### end if add user
	} ## end foreach keys

        if ($error_flag)
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Client error: One or more of the friends you added was not added because the username was invalid.";
	  return;
        }
     
        $res->{'success'} = "OK";
	$res->{"friends_added"} = $friends_added;
        return;
    }

    ###
    ### MODE: getevents
    ### given a selecttype and a selectwhat, returns events and eventids from the user's journal
    ###
    if ($req->{'mode'} eq "getevents")
    {
	my $drop_temp_table = "";

	my $midfields = "lt.event, lt.subject";
	if ($req->{'prefersubject'}) {
	    $midfields = "IF(LENGTH(lt.subject), lt.subject, lt.event) AS 'event'";
	}
	my $fields = "l.itemid, l.eventtime, $midfields, l.security, l.allowmask";
	my $allfields = "l.itemid, l.eventtime, lt.subject, lt.event, l.security, l.allowmask";
	
	### shared-journal support
	my $posterid = $userid;
	my $ownerid = $userid;
	my $qowner = $quser;

	if ($req->{'usejournal'}) {
            my $info = {};
	    if (&can_use_journal($dbh, $posterid, $req->{'usejournal'}, $info)) {
		$ownerid = $info->{'ownerid'};
		$qowner = $dbh->quote($req->{'usejournal'});
	    } else {
                $res->{'errmsg'} = $info->{'errmsg'};
	    }
	}
        if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }

	## why'd I introduce this redudant method into the protocol?
	if ($req->{'selecttype'} eq "one" && $req->{'itemid'} == -1) {
	    if ($ownerid != $posterid) {
		# we have to lookup lastitemid again
		$sth = $dbh->prepare("SELECT lastitemid FROM user WHERE userid=$ownerid");
		$sth->execute;
		($lastitemid) = $sth->fetchrow_array;		
	    }
	    if ($lastitemid) {
		### we know the last one the entered!
		$sth = $dbh->prepare("SELECT $fields FROM log l, logtext lt WHERE l.ownerid=$ownerid AND l.itemid=$lastitemid AND lt.itemid=$lastitemid");
	    } else  {
		### do it the slower way
		$req->{'selecttype'} = "lastn";
		$req->{'howmany'} = 1;
		undef $req->{'itemid'};
	    }
	}

	if ($req->{'selecttype'} eq "day")
	{
	    unless ($req->{'year'} =~ /^\d\d\d\d$/ && 
		    $req->{'month'} >= 1 && $req->{'month'} <= 12 &&
		    $req->{'day'} >= 1 && $req->{'day'} <= 31)
	    {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "User error: Invalid year, month, or day.";
		return;
	    }

	    my $qyear = $dbh->quote($req->{'year'});
	    my $qmonth = $dbh->quote($req->{'month'});
	    my $qday = $dbh->quote($req->{'day'});

	    ### MySQL sucks at this query for some reason, but it's fast if you go
	    ### to a temporary table and then select and order by on that

	    $dbh->do("DROP TABLE IF EXISTS tmp_selecttype_day");
	    $dbh->do("CREATE TEMPORARY TABLE tmp_selecttype_day SELECT $allfields, l.logtime FROM log l, logtext lt WHERE l.itemid=lt.itemid AND l.ownerid=$ownerid AND l.year=$qyear AND l.month=$qmonth AND l.day=$qday");

	    if ($dbh->err) {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "[1] Database error: " . $dbh->errstr;
		return;
	    }
       
	    $fields =~ s/lt\./l\./g;
	    $sth = $dbh->prepare("SELECT $fields FROM tmp_selecttype_day l ORDER BY l.eventtime, l.logtime");
	    $drop_temp_table = "tmp_selecttype_day";
	}
	elsif ($req->{'selecttype'} eq "lastn")
	{
	    my $beforedatewhere = "";
	    my $howmany = $req->{'howmany'} || 20;
	    if ($howmany > 50) { $howmany = 50; }
	    $howmany = $howmany + 0;
	    if ($req->{'beforedate'}) {
		unless ($req->{'beforedate'} =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/) {
		    $res->{'success'} = "FAIL";
		    $res->{'errmsg'} = "Client error: Invalid beforedate format.";
		    return;
		}
		$beforedatewhere = "AND l.eventtime < " . $dbh->quote($req->{'beforedate'});		
	    }

	    my @itemids = &get_recent_itemids($dbh, {
		'view' => 'lastn',
		'userid' => $ownerid,
		'remoteid' => $ownerid,
		'itemshow' => $MAX_HINTS_LASTN,
	    });
	    
            my $itemid_in = join(",", 0, @itemids);

            $sth = $dbh->prepare("SELECT $fields FROM log l, logtext lt WHERE l.itemid=lt.itemid AND l.itemid IN ($itemid_in) $beforedatewhere ORDER BY l.eventtime DESC, l.logtime DESC LIMIT $howmany");
	}
	elsif ($req->{'selecttype'} eq "one")
	{
	    if ($req->{'itemid'} > 0) {
		my $qitemid = $req->{'itemid'} + 0;
		$sth = $dbh->prepare("SELECT $fields FROM log l, logtext lt WHERE l.itemid=lt.itemid AND l.ownerid=$ownerid AND l.itemid=$qitemid");
	    }
	}
	elsif ($req->{'selecttype'} eq "syncitems") 
	{
	    my ($date);
	    ## have a valid date?
	    $date = $req->{'lastsync'};
	    if ($date) {
		if ($date !~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/) {
		    $res->{'success'} = "FAIL";
		    $res->{'errmsg'} = "Invalid date format";
		    return;
		}
	    } else {
		$date = "0000-00-00 00:00:00";
	    }

	    my $LIMIT = 300;
	    $sth = $dbh->prepare("SELECT $fields FROM log l, logtext lt, syncupdates s WHERE s.userid=$userid AND s.atime>='$date' AND s.nodetype='L' AND s.nodeid=l.itemid AND s.nodeid=lt.itemid ORDER BY s.atime LIMIT $LIMIT");
	}
	else 
	{
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Client error: Invalid selecttype.";
	    return;
	}

	$sth->execute;

	if ($dbh->err) {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "[2] Database error: " . $dbh->errstr;
	    return;
	}

	my $count = 0;
	my @itemids = ();
	while (my $row = $sth->fetchrow_hashref)
	{
	    $count++;
	    $res->{"events_${count}_itemid"} = $row->{'itemid'};
	    push @itemids, $row->{'itemid'};

	    $res->{"events_${count}_eventtime"} = $row->{'eventtime'};
	    if ($row->{'security'} ne "public") {
		$res->{"events_${count}_security"} = $row->{'security'};
		if ($row->{'security'} eq "usemask") {
		    $res->{"events_${count}_allowmask"} = $row->{'allowmask'};
		}
	    }
	    if ($row->{'subject'} ne "") {
		$row->{'subject'} =~ s/[\r\n]/ /g;
		$res->{"events_${count}_subject"} = $row->{'subject'};
	    }
	    if ($req->{'truncate'} >= 4) {
		if (length($row->{'event'}) > $req->{'truncate'}) {
		    $row->{'event'} = substr($row->{'event'}, 0, $req->{'truncate'}-3) . "...";
		}
	    }

	    my $event = $row->{'event'};
	    $event =~ s/\r//g;
	    if ($req->{'lineendings'} eq "unix") {
		# do nothing.
	    } elsif ($req->{'lineendings'} eq "mac") {
		$event =~ s/\n/\r/g;
	    } elsif ($req->{'lineendings'} eq "space") {
		$event =~ s/\n/ /g;
	    } elsif ($req->{'lineendings'} eq "dots") {
		$event =~ s/\n/ ... /g;
	    } else { # "pc"
		$event =~ s/\n/\r\n/g;
	    }

	    $res->{"events_${count}_event"} = &eurl($event);
	}
	$res->{'events_count'} = $count;

	if ($drop_temp_table) {
	    $dbh->do("DROP TABLE $drop_temp_table");
	}

	unless ($req->{'noprops'}) {
	    ### do the properties now
	    $count = 0;
	    my %props = ();
	    &load_log_props($dbh, \@itemids, \%props);
	    foreach my $itemid (keys %props) {
		foreach my $name (keys %{$props{$itemid}}) {
		    $count++;
		    $res->{"prop_${count}_itemid"} = $itemid;
		    $res->{"prop_${count}_name"} = $name;
		    my $value = $props{$itemid}->{$name};
		    $value =~ s/\n/ /g;
		    $res->{"prop_${count}_value"} = $value;
		}
	    }
	    $res->{'prop_count'} = $count;
	}

	$sth->finish;
        $res->{'success'} = "OK";
	return;
    }

    ###
    ### MODE: editevent
    ### given an itemid and event and eventtime, changes the event.  a blank event text implies deletion
    ### 
    if ($req->{'mode'} eq "editevent")
    {
        my $qitemid = $req->{'itemid'}+0;

	### shared-journal support
	my $posterid = $userid;
	my $ownerid = $userid;
	my $qowner = $quser;

	if ($req->{'usejournal'}) {
            my $info = {};
	    if (&can_use_journal($dbh, $posterid, $req->{'usejournal'}, $info)) {
		$ownerid = $info->{'ownerid'};
		$qowner = $dbh->quote($req->{'usejournal'});
	    } else {
                $res->{'errmsg'} = $info->{'errmsg'};
	    }
	}
        if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }

	## fetch the old entry, so we know what we really have to update. (less locking)
	my $oldevent = {};
	{
	    my $sth = $dbh->prepare("SELECT l.ownerid, l.posterid, l.eventtime, l.logtime, l.compressed, l.security, l.allowmask, l.year, l.month, l.day, lt.subject, MD5(lt.event) AS 'md5event' FROM log l, logtext lt WHERE l.itemid=$qitemid AND lt.itemid=$qitemid");
	    $sth->execute;
	    $oldevent = $sth->fetchrow_hashref;
	}

	### make sure this user is allowed to edit this entry
	if ($ownerid != $oldevent->{'ownerid'}) {
	    $res->{'errmsg'} = "Client error: This entry is not from your journal.";
	    $res->{'success'} = "FAIL"; 
	    return; 
	}
	if ($posterid != $oldevent->{'posterid'}) {
	    my $allow = 0;
	    if ($req->{'event'} !~ /\S/) {
		## deleting.  check to see if this person's a community maintainer.  (has 'sharedjournal' priv on it)
		my $quser = $dbh->quote($req->{'usejournal'});
		$sth = $dbh->prepare("SELECT COUNT(*) FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode='sharedjournal' AND pm.userid=$userid AND pm.arg=$quser");
		$sth->execute;
		my ($is_manager) = $sth->fetchrow_array;
		if ($is_manager) { $allow = 1; }
		
	    }
	    if (! $allow) {
		$res->{'errmsg'} = "You can only edit journal entries in shared journals that you posted.";
		$res->{'success'} = "FAIL"; 
		return; 
	    }
	}

	## update sync table (before we actually do it!  in case updates partially fail below)
	$dbh->do("REPLACE INTO syncupdates (userid, atime, nodetype, nodeid, atype) VALUES ($ownerid, NOW(), 'L', $qitemid, 'update')");
	
	# decide whether we're updating or deleting the entry
	if ($req->{'event'} =~ /\S/)
	{
	    # update
	    # date validation
	    if ($req->{'year'} !~ /^\d\d\d\d$/ || $req->{'year'} < 1980 || $req->{'year'} > 2037) {
		$res->{'errmsg'} = "Client error: Invalid year value.";
	    }
	    if ($req->{'mon'} !~ /^\d{1,2}$/ || $req->{'mon'} < 1 || $req->{'mon'} > 12) {
		$res->{'errmsg'} = "Client error: Invalid month value.";
	    }
	    if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }
	    if ($req->{'day'} !~ /^\d{1,2}$/ || $req->{'day'} < 1 || $req->{'day'} > &days_in_month($req->{'month'}, $req->{'year'})) {
		$res->{'errmsg'} = "Client error: Invalid day of month value.";
	    }
	    if ($req->{'hour'} !~ /^\d{1,2}$/ || $req->{'hour'} < 0 || $req->{'hour'} > 23) {
		$res->{'errmsg'} = "Client error: Invalid hour value.";
	    }
	    if ($req->{'min'} !~ /^\d{1,2}$/ || $req->{'min'} < 0 || $req->{'min'} > 59) {
		$res->{'errmsg'} = "Client error: Invalid minute value.";
	    }

	    ### load existing meta-data
	    my %curprops;
	    &LJ::load_log_props($dbh, [ $qitemid ], \%curprops);

	    ## handle meta-data (properties)
	    my %props_byname = ();
	    my %props = ();
	    foreach my $key (keys %{$req}) {
		next unless ($key =~ /^prop_(\w+)$/);

		## changing to something else?
		if ($curprops{$qitemid}->{$1} ne $req->{$key}) {
		    $props_byname{$1} = $req->{$key};
		}
	    }

	    if (%props_byname) {
		my $qnamein = join(",", map { $dbh->quote($_); } keys %props_byname);
		my $sth = $dbh->prepare("SELECT propid, name, datatype FROM logproplist WHERE name IN ($qnamein)");
		$sth->execute;
		while ($_ = $sth->fetchrow_hashref) {
		    if ($_->{'datatype'} eq "bool" && $props_byname{$_->{'name'}} !~ /^[01]$/) {
			$res->{'errmsg'} = "Client error: Property \"$_->{'name'}\" should be 0 or 1";
		    }
		    if ($_->{'datatype'} eq "num" && $props_byname{$_->{'name'}} =~ /[^\d]/) {
			$res->{'errmsg'} = "Client error: Property \"$_->{'name'}\" should be numeric";
		    }
		    $props{$_->{'propid'}} = $props_byname{$_->{'name'}};
		    delete $props_byname{$_->{'name'}};
		}
		if (%props_byname) {
		    $res->{'errmsg'} = "Client error: Unknown property: " . join(",", keys %props_byname);
		}
	    }

	    if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }

	    #### clean up the event text        
	    my $event = $req->{'event'};
	    
	    # remove surrounding whitespace
	    $event =~ s/^\s+//;
	    $event =~ s/\s+$//;
	    
	    # convert line endings to unix format
	    if ($req->{'lineendings'} eq "mac") {
		$event =~ s/\r/\n/g;
	    } else {
		$event =~ s/\r//g;
	    }
	    my $qevent = $dbh->quote($event);
	    $event = "";
	    
	    my $eventtime = sprintf("%04d-%02d-%02d %02d:%02d", $req->{'year'}, $req->{'mon'}, $req->{'day'}, $req->{'hour'}, $req->{'min'});
	    my $qeventtime = $dbh->quote($eventtime);

	    my $qallowmask = $req->{'allowmask'}+0;
	    my $security = "public";
	    if ($req->{'security'} eq "private" || $req->{'security'} eq "usemask") {
		$security = $req->{'security'};
	    }

	    my $qyear = $req->{'year'}+0;
	    my $qmonth = $req->{'mon'}+0;
	    my $qday = $req->{'day'}+0;

	    if ($qyear != $oldevent->{'year'} ||
		$qmonth != $oldevent->{'month'} ||
		$qday != $oldevent->{'day'} ||
		$eventtime ne $oldevent->{'eventtime'} ||
		$security ne $oldevent->{'security'} ||
		$qallowmask != $oldevent->{'allowmask'}
		)
	    {
		$qsecurity = $dbh->quote($security);
		$sth = $dbh->prepare("UPDATE log SET eventtime=$qeventtime, year=$qyear, month=$qmonth, day=$qday, security=$qsecurity, allowmask=$qallowmask WHERE itemid=$qitemid");
		$sth->execute;
	    }

	    if ($security ne $oldevent->{'security'} ||
		$qallowmask != $oldevent->{'allowmask'})
	    {
		if ($security eq "public" || $security eq "private") {
		    $dbh->do("DELETE FROM logsec WHERE ownerid=$ownerid AND itemid=$qitemid");
		} else {
		    $qsecurity = $dbh->quote($security);
		    $dbh->do("REPLACE INTO logsec (ownerid, itemid, allowmask) VALUES ($ownerid, $qitemid, $qallowmask)");		    
		}
	    }

	    if (Digest::MD5::md5_hex($event) ne $oldevent->{'md5event'} ||
		$req->{'subject'} ne $oldevent->{'subject'})
	    {
		my $qsubject = $dbh->quote($req->{'subject'});	    

		$sth = $dbh->prepare("UPDATE logtext SET event=$qevent, subject=$qsubject WHERE itemid=$qitemid");
		$sth->execute;
		$dbh->do("REPLACE INTO logsubject (itemid, subject) VALUES ($qitemid, $qsubject)");
	    }


	    if ($dbh->err) {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "Database error [lt]: " . $dbh->errstr;
		return;
	    }

	    if (%props) {
		my $propinsert = "";
		my @props_to_delete;
		foreach my $propid (keys %props) {
		    unless ($props{$propid}) {
			push @props_to_delete, $propid;
			next;
		    }
		    if ($propinsert) {
			$propinsert .= ", ";
		    } else {
			$propinsert = "REPLACE INTO logprop (itemid, propid, value) VALUES ";
		    }
		    my $qvalue = $dbh->quote($props{$propid});
		    $propinsert .= "($qitemid, $propid, $qvalue)";
		}
		if ($propinsert) { $dbh->do($propinsert); }
		
		if (@props_to_delete) {
		    my $propid_in = join(", ", @props_to_delete);
		    $dbh->do("DELETE FROM logprop WHERE itemid=$qitemid AND propid IN ($propid_in)");
		}
	    }

	    ## update lastn hints table, unless it was a backdated entry before and they didn't
	    ## say in their request what its new backdated status is:

	    if ($req->{'prop_opt_backdated'} eq "1") {
		&LJ::query_buffer_add($dbh, "hintlastnview", "DELETE FROM hintlastnview WHERE userid=$ownerid AND itemid=$qitemid");
	    } else {
		unless ($curprops{$qitemid}->{'opt_backdated'} && ! defined $req->{'prop_opt_backdated'})
		{
		    &LJ::query_buffer_add($dbh, "hintlastnview", "REPLACE INTO hintlastnview (userid, itemid) VALUES ($ownerid, $qitemid)");
		}
	    }

	}
	else
	{
	    &LJ::delete_item($dbh, $ownerid, $req->{'itemid'});
	}
	
	if ($dbh->err) {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Database error [966]: " . $dbh->errstr;
	    return;
	}
	
        $res->{'success'} = "OK";
        return 1;
    }

    ###
    ### MODE: postevent
    ### 
    if ($req->{'mode'} eq "postevent")
    {
        if ($req->{'event'} =~ /^\s*$/)
        {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Client error: No event specified.";
	    return;
        }
	
	### make sure community, shared, or news journals don't post
	### note: shared and news journals are deprecated.  every shared journal should one day
	###       be a community journal, of some form.
	if ($journaltype eq "C" || $journaltype eq "S" || $journaltype eq "N") {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "User error: Community and shared journals cannot post, only be posted into.";
	    return;
	}


	#### clean up the event text        
	my $event = $req->{'event'};
	
	# remove surrounding whitespace
	$event =~ s/^\s+//;
	$event =~ s/\s+$//;
	
	# convert line endings to unix format
	if ($req->{'lineendings'} eq "mac") {
	    $event =~ s/\r/\n/g;
	} else {
	    $event =~ s/\r//g;
	}
        
        # date validation
        if ($req->{'year'} !~ /^\d\d\d\d$/ || $req->{'year'} < 1980 || $req->{'year'} > 2037) {
	    $res->{'errmsg'} = "Client error: Invalid year value.";
	}
        if ($req->{'mon'} !~ /^\d{1,2}$/ || $req->{'mon'} < 1 || $req->{'mon'} > 12) {
	    $res->{'errmsg'} = "Client error: Invalid month value.";
	}
        if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }
        if ($req->{'day'} !~ /^\d{1,2}$/ || $req->{'day'} < 1 || $req->{'day'} > &days_in_month($req->{'month'}, $req->{'year'})) {
	    $res->{'errmsg'} = "Client error: Invalid day of month value.";
	}
        if ($req->{'hour'} !~ /^\d{1,2}$/ || $req->{'hour'} < 0 || $req->{'hour'} > 23) {
	    $res->{'errmsg'} = "Client error: Invalid hour value.";
        }
        if ($req->{'min'} !~ /^\d{1,2}$/ || $req->{'min'} < 0 || $req->{'min'} > 59) {
	    $res->{'errmsg'} = "Client error: Invalid minute value.";
        }
	
	## handle meta-data (properties)
	my %props_byname = ();
	my %props = ();
	foreach my $key (keys %{$req}) {
	    next unless ($key =~ /^prop_(\w+)$/);
	    next unless ($req->{$key});  # make sure it was non-empty/true interesting value
	    $props_byname{$1} = $req->{$key};
	}
	if (%props_byname) {
	    my $qnamein = join(",", map { $dbh->quote($_); } keys %props_byname);
	    my $sth = $dbh->prepare("SELECT propid, name, datatype FROM logproplist WHERE name IN ($qnamein)");
	    $sth->execute;
	    while ($_ = $sth->fetchrow_hashref) {
		if ($_->{'datatype'} eq "bool" && $props_byname{$_->{'name'}} !~ /^[01]$/) {
		    $res->{'errmsg'} = "Client error: Property \"$_->{'name'}\" should be 0 or 1";
		}
		if ($_->{'datatype'} eq "num" && $props_byname{$_->{'name'}} =~ /[^\d]/) {
		    $res->{'errmsg'} = "Client error: Property \"$_->{'name'}\" should be numeric";
		}
		$props{$_->{'propid'}} = $props_byname{$_->{'name'}};
		delete $props_byname{$_->{'name'}};
	    }
	    if (%props_byname) {
		$res->{'errmsg'} = "Client error: Unknown property: " . join(",", keys %props_byname);
	    }
	}

	### allow for posting to journals that aren't yours (if you have permission)
	my $posterid = $userid;
	my $ownerid = $userid;
	my $qowner = $quser;

	if ($req->{'usejournal'}) {
	    my $info = {};
	    if (&can_use_journal($dbh, $posterid, $req->{'usejournal'}, $info)) {
		$ownerid = $info->{'ownerid'};
		$qowner = $dbh->quote($req->{'usejournal'});
	    } else {
		$res->{'errmsg'} = $info->{'errmsg'};
	    }
	}
	
	### communities can't post. 
	if ($journaltype ne "P") {
	    $res->{'errmsg'} = "Sorry, community and other shared accounts can only be posted into, they cannot post themselves.";
	}

	if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }
	    
        # make the proper date format
        my $qeventtime = $dbh->quote(sprintf("%04d-%02d-%02d %02d:%02d", $req->{'year'}, $req->{'mon'}, $req->{'day'}, $req->{'hour'}, $req->{'min'}));

	my $qsubject = $dbh->quote($req->{'subject'});
	my $qallowmask = $req->{'allowmask'}+0;
	my $qsecurity = "public";
	my $uselogsec = 0;
	if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
	    $qsecurity = $req->{'security'};
	}
	if ($req->{'security'} eq "usemask") {  
	    $uselogsec = 1; 
	}
	$qsecurity = $dbh->quote($qsecurity);

	### make sure user can't post with "custom security" on shared journals
	if ($req->{'security'} eq "usemask" && 
	    $qallowmask != 1 && ($ownerid != $posterid)) 
	{
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "Sorry, you can't use custom security on shared journals.  Change security to public, private, or friends and post again.";
	    return;
	}

	### do processing of embedded polls
	my @polls = ();
	if (LJ::Poll::contains_new_poll(\$event))
	{
	    if ($paidfeatures ne "paid" && $paidfeatures ne "on") {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "Sorry, only users with paid accounts can create polls in their journals.";
		return;
	    }
	    my $error = "";
	    @polls = LJ::Poll::parse($dbh, \$event, \$error, {
		'journalid' => $ownerid,
		'posterid' => $posterid,
	    });
	    if ($error) {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = $error;
		return;
	    }
	}

	my $qownerid = $ownerid+0;
	my $qposterid = $posterid+0;

	$dbh->do("INSERT INTO log (ownerid, posterid, eventtime, logtime, security, allowmask, replycount, year, month, day) VALUES ($qownerid, $qposterid, $qeventtime, NOW(), $qsecurity, $qallowmask, 0, $req->{'year'}, $req->{'mon'}, $req->{'day'})");

        if ($dbh->err) {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Database error [log]: " . $dbh->errstr;
	  return;
        }

	my $itemid = $dbh->{'mysql_insertid'};

	unless ($itemid) {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Database error: no itemid could be generated.";
	  return;
	}

	### finish embedding stuff now that we have the itemid
	{
	    ### this should NOT return an error, and we're mildly fucked by now
	    ### if it does (would have to delete the log row up there), so we're
	    ### not going to check it for now.

	    my $error = "";
	    &LJ::Poll::register($dbh, \$event, \$error, $itemid, @polls);
	}
	#### /embedding

        my $qevent = $dbh->quote($event);
	$event = "";
	$dbh->do("INSERT INTO logtext (itemid, subject, event) VALUES ($itemid, $qsubject, $qevent)");
	$dbh->do("INSERT INTO logsubject (itemid, subject) VALUES ($itemid, $qsubject)");
	
	## update sync table
	$dbh->do("REPLACE INTO syncupdates (userid, atime, nodetype, nodeid, atype) SELECT ownerid, logtime, 'L', itemid, 'create' FROM log WHERE itemid=$itemid");

	if ($uselogsec) {
	    $dbh->do("INSERT INTO logsec (ownerid, itemid, allowmask) VALUES ($qownerid, $itemid, $qallowmask)");
	}

        if ($dbh->err) {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Database error [ch]: " . $dbh->errstr;
	  return;
        }

	if (%props) {
	    my $propinsert = "";
	    foreach my $propid (keys %props) {
		if ($propinsert) {
		    $propinsert .= ", ";
		} else {
		    $propinsert = "INSERT INTO logprop (itemid, propid, value) VALUES ";
		}
		my $qvalue = $dbh->quote($props{$propid});
		$propinsert .= "($itemid, $propid, $qvalue)";
	    }
	    if ($propinsert) { $dbh->do($propinsert); }
	}
        
        $dbh->do("UPDATE user SET timeupdate=NOW(), lastitemid=$itemid WHERE userid=$qownerid");

	if ($track eq "yes") {
	    my $quserid = $userid+0;
	    my $qip = $dbh->quote($ENV{'REMOTE_ADDR'});
	    $dbh->do("INSERT INTO tracking (userid, acttime, ip, actdes, associd) VALUES ($quserid, NOW(), $qip, 'post', $itemid)");
	}

        if ($dbh->err) {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "(report this) Database error (hfv): " . $dbh->errstr;
	  return;
        }

	unless ($req->{'prop_opt_backdated'}) {
	    ## update lastn hints table
	    &LJ::query_buffer_add($dbh, "hintlastnview", "INSERT INTO hintlastnview (userid, itemid) VALUES ($qownerid, $itemid)");
	}
	    
        if ($dbh->err) {
	    $res->{'success'} = "FAIL";
	    $res->{'errmsg'} = "(report this) Database error (hlnv): " . $dbh->errstr;
	    return;
        }

	#### do the ICQ notifications
	if (0 || $user eq "test") {
	    # $sth = $dbh->prepare("SELECT u.user, u.icq FROM friends f, user u WHERE f.user=u.user AND f.friend=$quser AND u.icq <> ''");
	    # $sth->execute;
	    while (my $f = $sth->fetchrow_hashref) 
	    {
		my $msg = "";
		$msg .= "Your friend \"$user\" updated their journal...\r\n";
		$msg .= "$LJ::SITEROOT/users/$f->{'user'}/friends\r\n\r\n";
		$msg .= "\"$req->{'event'}\"";
		# &icq_send($f->{'icq'}, $msg);
	    }
	}
        
        $res->{'success'} = "OK";
	$res->{'itemid'} = $itemid;  # by request of martmart
        return 1;
    }

    ###
    ### MODE: syncitems
    ### 
    if ($req->{'mode'} eq "syncitems")
    {
	my ($date, $sth);

	## have a valid date?
	$date = $req->{'lastsync'};
	if ($date) {
	    if ($date !~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/) {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "Invalid date format";
		return;
	    }
	} else {
	    $date = "0000-00-00 00:00:00";
	}

	my $LIMIT = 500;

	$sth = $dbh->prepare("SELECT COUNT(*) FROM syncupdates WHERE userid=$userid AND atime >= '$date'");
	$sth->execute;
	my ($sync_count) = $sth->fetchrow_array;
	
	$sth = $dbh->prepare("SELECT atime, nodetype, nodeid, atype FROM syncupdates WHERE userid=$userid AND atime >= '$date' ORDER BY atime LIMIT $LIMIT");
	$sth->execute;
	if ($dbh->err) {
	    $res->{'errmsg'} = $dbh->errstr;
	    $res->{'success'} = "FAIL";
	    return 0;
	}
	my $ct = 0;
	while (my ($atime, $nodetype, $nodeid, $atype) = $sth->fetchrow_array) {
	    $ct++;
	    $res->{"sync_${ct}_item"} = "$nodetype-$nodeid";
	    $res->{"sync_${ct}_action"} = $atype;
	    $res->{"sync_${ct}_time"} = $atime;
	}
	$res->{'sync_count'} = $ct;
	$res->{'sync_total'} = $sync_count;

        $res->{'success'} = "OK";
        return 1;
    }

    ###
    ### MODE: checkfriends
    ### 
    if ($req->{'mode'} eq "checkfriends")
    {
	my ($lastdate, $sth);

	## have a valid date?
	$lastupdate = $req->{'lastupdate'};
	if ($lastupdate) {
	    if ($lastupdate !~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/) {
		$res->{'success'} = "FAIL";
		$res->{'errmsg'} = "Invalid date format";
		return;
	    }
	} else {
	    $lastupdate = "0000-00-00 00:00:00";
	}

	my $sql = "SELECT MAX(u.timeupdate) FROM user u, friends f WHERE u.userid=f.friendid AND f.userid=$userid";
	if ($req->{'mask'} and $req->{'mask'} !~ /\D/) {
	    $sql .= " AND f.groupmask & $req->{mask} > 0";
	}
	
	$sth = $dbh->prepare($sql);
	$sth->execute;
	my ($update) = $sth->fetchrow_array;
	$update ||= "0000-00-00 00:00:00";

	if ($req->{'lastupdate'} && $update gt $lastupdate) {
	    $res->{'new'} = 1;
	} else {
	    $res->{'new'} = 0;
	}

	$res->{'lastupdate'} = $update;

	if ($paidfeatures eq "on" || $paidfeatures eq "paid") {
	    $res->{'interval'} = 30;
	} else {
	    $res->{'interval'} = 60;
	}


	$res->{'success'} = "OK";
        return 1;
    }
       


    ### unknown mode!
    $res->{'success'} = "FAIL";
    $res->{'errmsg'} = "Client error: Unknown mode ($req->{'mode'})";
    return;
}

1;
