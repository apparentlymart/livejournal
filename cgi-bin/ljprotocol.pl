#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

#### New interface (meta handler) ... other handlers should call into this.
package LJ::Protocol;

sub error_message
{
    my $code = shift;
    my %e = (
	     # User Errors
	     "100" => "Invalid username",
	     "101" => "Invalid password",
	     "102" => "Can't use custom security on shared/community journals.",
	     "103" => "Poll error",
	     "150" => "Can't post as non-user",

	     # Client Errors
	     "200" => "Missing required argument(s)",
	     "201" => "Unknown method",
	     "202" => "Too many arguments",
	     "203" => "Invalid argument(s)",
	     "204" => "Invalid metadata datatype",
	     "205" => "Unknown metadata",

	     # Access Errors
	     "300" => "Don't have access to shared/community journal",
	     "301" => "Access of restricted feature",

	     # Server Errors
	     "500" => "Internal server error",
	     "501" => "Database error",
	     );

    my $prefix = "";
    if ($code >= 200) { $prefix = "Client error: "; }
    if ($code >= 500) { $prefix = "Server error: "; }
    return "$prefix$e{$code}";
}

# returns result, or undef on failure
sub do_request 
{
    # get the request and response hash refs
    my ($method, $req, $err, $flags) = @_;
    my $dbs = LJ::get_dbs();
    $flags ||= {};
    my @args = ($dbs, $req, $err, $flags);

    return fail($err,500) unless $dbs;
    
    if ($method eq "login")           { return login(@args);           }
    if ($method eq "getfriendgroups") { return getfriendgroups(@args); }
    if ($method eq "getfriends")      { return getfriends(@args);      }
    if ($method eq "friendof")        { return friendof(@args);        }
    if ($method eq "checkfriends")    { return checkfriends(@args);    }
    if ($method eq "getdaycounts")    { return getdaycounts(@args);    }
    if ($method eq "postevent")       { return postevent(@args);       }
    if ($method eq "syncitems")       { return syncitems(@args);       }

    return fail($err,201);    
}

sub login
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);

    my $dbh = $dbs->{'dbh'};
    my $u = $flags->{'u'};    
    my $res = {};

    ## return a message to the client to be displayed (optional)
    login_message($dbs, $req, $res, $flags);

    ## report what shared journals this user may post in
    $res->{'usejournals'} = list_usejournals($dbs, $u);

    ## return their friend groups
    $res->{'friendgroups'} = list_friendgroups($dbs, $u);

    ## if they gave us a number of moods to get higher than, then return them
    if (defined $req->{'getmoods'}) {
	$res->{'moods'} = list_moods($dbs, $req->{'getmoods'});
    }

    ### picture keywords, if they asked for them.
    if ($req->{'getpickws'}) {
	$res->{'pickws'} = list_pickws($dbs, $u);
    }

    ## return client menu tree, if requested
    if ($req->{'getmenus'}) {
	$res->{'menus'} = hash_menus($dbs, $u);
    }

    ## tell paid users they can hit the fast servers later.
    if ($u->{'paidfeatures'} eq "on" || $u->{'paidfeatures'} eq "paid") {
	$res->{'fastserver'} = 1;
    }

    ## user info
    $res->{'userid'} = $u->{'userid'};
    $res->{'fullname'} = $u->{'name'};

    ## update or add to clientusage table
    if ($req->{'clientversion'} =~ /^\S+\/\S+$/)  {
	my $qclient = $dbh->quote($req->{'clientversion'});
	my $cu_sql = "REPLACE INTO clientusage (userid, clientid, lastlogin) " .
	    "SELECT $u->{'userid'}, clientid, NOW() FROM clients WHERE client=$qclient";
	my $sth = $dbh->prepare($cu_sql);
	$sth->execute;
	unless ($sth->rows) {
	    # only way this can be 0 is if client doesn't exist in clients table, so
	    # we need to add a new row there, to get a new clientid for this new client:
	    $dbh->do("INSERT INTO clients (client) VALUES ($qclient)");
	    # and now we can do the query from before and it should work:
	    $sth = $dbh->prepare($cu_sql);
	    $sth->execute;
	}
    }

    return $res;
}

sub getfriendgroups
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};    
    my $res = {};
    $res->{'friendgroups'} = list_friendgroups($dbs, $u);
    return $res;
}

sub getfriends
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};    
    my $res = {};
    if ($req->{'includegroups'}) {
	$res->{'friendgroups'} = list_friendgroups($dbs, $u);
    }
    if ($req->{'includefriendof'}) {
	$res->{'friendofs'} = list_friends($dbs, $u, {
	    'limit' => $req->{'friendoflimit'},
	    'friendof' => 1,
	});
    }
    $res->{'friends'} = list_friends($dbs, $u, {
	'limit' => $req->{'friendlimit'} 
    });
    return $res;
}

sub friendof
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};    
    my $res = {};
    $res->{'friendofs'} = list_friends($dbs, $u, {
	'friendof' => 1,
	'limit' => $req->{'friendoflimit'},
    });
    return $res;
}

sub checkfriends
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};    
    my $res = {};

    my $dbr = $dbs->{'reader'};
    my ($lastdate, $sth);

    ## have a valid date?
    my $lastupdate = $req->{'lastupdate'};
    if ($lastupdate) {
	return fail($err,203) unless
	    ($lastupdate =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
	$lastupdate = "0000-00-00 00:00:00";
    }

    my $sql = "SELECT MAX(u.timeupdate) FROM userusage u, friends f WHERE u.userid=f.friendid AND f.userid=$u->{'userid'}";
    if ($req->{'mask'} and $req->{'mask'} !~ /\D/) {
	$sql .= " AND f.groupmask & $req->{mask} > 0";
    }
	
    $sth = $dbr->prepare($sql);
    $sth->execute;
    my ($update) = $sth->fetchrow_array;
    $update ||= "0000-00-00 00:00:00";

    if ($req->{'lastupdate'} && $update gt $lastupdate) {
	$res->{'new'} = 1;
    } else {
	$res->{'new'} = 0;
    }
    
    $res->{'lastupdate'} = $update;

    if ($u->{'paidfeatures'} eq "on" || $u->{'paidfeatures'} eq "paid") {
	$res->{'interval'} = 30;
    } else {
	$res->{'interval'} = 60;
    }

    return $res;
}

sub getdaycounts
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};    
    my $ownerid = $flags->{'ownerid'};
    my $dbr = $dbs->{'reader'};
    
    my $res = {};

    my $sth = $dbr->prepare("SELECT year, month, day, COUNT(*) AS 'count' FROM log WHERE ownerid=$ownerid GROUP BY 1, 2, 3");
    $sth->execute;
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
	my $date = sprintf("%04d-%02d-%02d", $y, $m, $d);
	push @{$res->{'daycounts'}}, { 'date' => $date, 'count' => $c };
    }
    return $res;
}

sub postevent
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};    
    my $ownerid = $flags->{'ownerid'};
    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};

    return fail($err,200) unless ($req->{'event'} =~ /\S/);
    
    ### make sure community, shared, or news journals don't post
    ### note: shared and news journals are deprecated.  every shared journal 
    ##        should one day be a community journal, of some form.
    return fail($err,150) if ($u->{'journaltype'} eq "C" || 
			      $u->{'journaltype'} eq "S" ||
			      $u->{'journaltype'} eq "N");

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
	return fail($err,203,"Invalid year value.");
    }
    if ($req->{'mon'} !~ /^\d{1,2}$/ || $req->{'mon'} < 1 || $req->{'mon'} > 12) {
	return fail($err,203,"Invalid month value.");
    }
    if ($req->{'day'} !~ /^\d{1,2}$/ || $req->{'day'} < 1 || 
	$req->{'day'} > LJ::days_in_month($req->{'month'}, $req->{'year'})) {
	return fail($err,203,"Invalid day of month value.");
    }
    if ($req->{'hour'} !~ /^\d{1,2}$/ || $req->{'hour'} < 0 || $req->{'hour'} > 23) {
	return fail($err,203,"Invalid hour value.");
    }
    if ($req->{'min'} !~ /^\d{1,2}$/ || $req->{'min'} < 0 || $req->{'min'} > 59) {
	return fail($err,203,"Invalid minute value.");
    }
	
    ## handle meta-data (properties)
    my %props_byname = ();
    my %props = ();
    foreach my $key (keys %{$req->{'props'}}) {
	next unless ($req->{'props'}->{$key});  # make sure it was non-empty/true interesting value
	$props_byname{$key} = $req->{'props'}->{$key};
    }
    if (%props_byname) {
	my $qnamein = join(",", map { $dbh->quote($_); } keys %props_byname);
	my $sth = $dbr->prepare("SELECT propid, name, datatype FROM logproplist WHERE name IN ($qnamein)");
	$sth->execute;
	while (my ($pid, $pname, $ptype) = $sth->fetchrow_array) {
	    if ($ptype eq "bool" && $props_byname{$pname} !~ /^[01]$/) {
		return fail($err,204,"Property \"$pname\" should be 0 or 1");
	    }
	    if ($ptype eq "num" && $props_byname{$pname} =~ /[^\d]/) {
		return fail($err,204,"Property \"$pname\" should be numeric");
	    }
	    $props{$pid} = $props_byname{$pname};
	    delete $props_byname{$pname};
	}
	return fail($err,205,join(",",keys %props_byname)) 
	    if (%props_byname);
    }
    
    ### allow for posting to journals that aren't yours (if you have permission)
    my $posterid = $u->{'userid'};
    my $ownerid = $flags->{'ownerid'};
	
    # make the proper date format
    my $qeventtime = $dbh->quote(sprintf("%04d-%02d-%02d %02d:%02d", 
					 $req->{'year'}, $req->{'mon'}, 
					 $req->{'day'}, $req->{'hour'}, 
					 $req->{'min'}));
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
    return fail($err,102) 
	if ($req->{'security'} eq "usemask" && 
	    $qallowmask != 1 && ($ownerid != $posterid));
    
    ### do processing of embedded polls
    my @polls = ();
    if (LJ::Poll::contains_new_poll(\$event))
    {
	return fail($err,301,"Only users with paid accounts can create polls in their journals.")
	    if ($u->{'paidfeatures'} ne "paid" && $u->{'paidfeatures'} ne "on");
	
	my $error = "";
	@polls = LJ::Poll::parse($dbh, \$event, \$error, {
	    'journalid' => $ownerid,
	    'posterid' => $posterid,
	});
	return fail($err,103,$error) if $error;
    }
    
    my $qownerid = $ownerid+0;
    my $qposterid = $posterid+0;
    
    $dbh->do("INSERT INTO log (ownerid, posterid, eventtime, logtime, security, allowmask, replycount, year, month, day) VALUES ($qownerid, $qposterid, $qeventtime, NOW(), $qsecurity, $qallowmask, 0, $req->{'year'}, $req->{'mon'}, $req->{'day'})");
    return fail($err,501,$dbh->errstr) if $dbh->err;

    my $itemid = $dbh->{'mysql_insertid'};
    return fail($err,501,"No itemid could be generated.") unless $itemid;
    
    ### finish embedding stuff now that we have the itemid
    {
	### this should NOT return an error, and we're mildly fucked by now
	### if it does (would have to delete the log row up there), so we're
	### not going to check it for now.
	
	my $error = "";
	LJ::Poll::register($dbh, \$event, \$error, $itemid, @polls);
    }
    #### /embedding
    
    my $qevent = $dbh->quote($event);
    $event = "";
    
    my @prefix = ("");
    if ($LJ::USE_RECENT_TABLES) { push @prefix, "recent_"; }
    foreach my $pfx (@prefix) 
    {
	$dbh->do("INSERT INTO ${pfx}logtext (itemid, subject, event) ".
		 "VALUES ($itemid, $qsubject, $qevent)");
	if ($dbh->err) {
	    my $msg = $dbh->errstr;
	    LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
	    return fail($err,501,$msg);
	}
    }
    
    # this is to speed month view and other places that don't need full text.
    $dbh->do("INSERT INTO logsubject (itemid, subject) VALUES ($itemid, $qsubject)");
    if ($dbh->err) {
	my $msg = $dbh->errstr;
        LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
	return fail($err,501,$msg);
    }
    
    ## update sync table
    $dbh->do("REPLACE INTO syncupdates (userid, atime, nodetype, nodeid, atype) ".
	     "SELECT ownerid, logtime, 'L', itemid, 'create' FROM log WHERE itemid=$itemid");
    if ($dbh->err) {
	my $msg = $dbh->errstr;
        LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
	return fail($err,501,$msg);
    }
    
    # keep track of custom security stuff in other table.
    if ($uselogsec) {
	$dbh->do("INSERT INTO logsec (ownerid, itemid, allowmask) VALUES ($qownerid, $itemid, $qallowmask)");
	if ($dbh->err) {
	    my $msg = $dbh->errstr;
  	    LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
	    return fail($err,501,$msg);
	}
    }
    
    # meta-data
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
	if ($propinsert) { 
	    $dbh->do($propinsert); 
	    if ($dbh->err) {
		my $msg = $dbh->errstr;
	        LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
		return fail($err,501,$msg);
	    }
	}
    }
    
    $dbh->do("UPDATE userusage SET timeupdate=NOW(), lastitemid=$itemid ".
	     "WHERE userid=$qownerid");
    
    if ($u->{'track'} eq "yes") {
	my $quserid = $u->{'userid'}+0;
	my $qip = $dbh->quote($ENV{'REMOTE_ADDR'});
	$dbh->do("INSERT INTO tracking (userid, acttime, ip, actdes, associd) ".
		 "VALUES ($quserid, NOW(), $qip, 'post', $itemid)");
    }
    
    unless ($req->{'props'}->{"opt_backdated"}) {
	## update lastn hints table
	LJ::query_buffer_add($dbh, "hintlastnview", 
			     "INSERT INTO hintlastnview (userid, itemid) ".
			     "VALUES ($qownerid, $itemid)");
    }
    
    my $res = {};
    $res->{'itemid'} = $itemid;  # by request of mart
    return $res;
}

sub list_friends
{
    my ($dbs, $u, $opts) = @_;
    my $dbr = $dbs->{'reader'};

    my $limitnum = $opts->{'limit'}+0;
    my $where = "u.userid=f.friendid AND f.userid=$u->{'userid'}";
    if ($opts->{'friendof'}) {
	$where = "u.userid=f.userid AND f.friendid=$u->{'userid'}";
    }

    my $limit = $limitnum ? "LIMIT $limitnum" : "";
    my $sth = $dbr->prepare("SELECT u.user AS 'friend', u.name, u.journaltype, f.fgcolor, f.bgcolor, f.groupmask FROM user u, friends f WHERE $where AND u.statusvis='V' ORDER BY u.user $limit");
    $sth->execute;
    my @friends;
    push @friends, $_ while $_ = $sth->fetchrow_hashref;
    $sth->finish;

    my $res = [];
    foreach my $f (@friends)
    {
	my $r =  { 'username' => $f->{'friend'},
		   'fullname' => $f->{'name'},
	       };
	$r->{'fgcolor'} = $f->{'fgcolor'} if ($f->{'fgcolor'});
	$r->{'bgcolor'} = $f->{'bgcolor'} if ($f->{'bgcolor'});
	if (! $opts->{'friendof'} && $f->{'groupmask'} != 1) {
	    $r->{"groupmask"} = $f->{'groupmask'};
	}
	if ($f->{'journaltype'} eq "C") {
	    $r->{"type"} = "community";
	}
	
	push @$res, $r;
    }
    return $res;
}

sub syncitems
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);
    
    my $ownerid = $flags->{'ownerid'};
    my $dbr = $dbs->{'reader'};
    my ($date, $sth);

    ## have a valid date?
    $date = $req->{'lastsync'};
    if ($date) {
	return fail($err,203,"Invalid date format")
	    unless ($date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
	$date = "0000-00-00 00:00:00";
    }

    my $LIMIT = 500;

    $sth = $dbr->prepare("SELECT COUNT(*) FROM syncupdates WHERE ".
			 "userid=$ownerid AND atime >= '$date'");
    $sth->execute;
    my ($sync_count) = $sth->fetchrow_array;
	
    $sth = $dbr->prepare("SELECT atime, nodetype, nodeid, atype FROM ".
			 "syncupdates WHERE userid=$ownerid AND ".
			 "atime >= '$date' ORDER BY atime LIMIT $LIMIT");
    $sth->execute;
    return fail($err,501,$dbr->errstr) if $dbr->err;

    my $res = {};
    my $list = $res->{'syncitems'} = [];
    my $ct = 0;
    while (my ($atime, $nodetype, $nodeid, $atype) = $sth->fetchrow_array) {
	$ct++;
	push @$list, { 'item' => "$nodetype-$nodeid",
		       'action' => $atype,
		       'time' => $atime,
		   };
    }
    $res->{'count'} = $ct;
    $res->{'total'} = $sync_count;
    return $res;
}

sub login_message
{
    my ($dbs, $req, $res, $flags) = @_;

    my $u = $flags->{'u'};

    if ($u eq "test") { 
	$res->{'message'} = "Hello Test Account!"; 
    }
    if ($req->{'clientversion'} =~ /^Win32-MFC\/(1.2.[0123456])$/ ||
	$req->{'clientversion'} =~ /^Win32-MFC\/(1.3.[01234])\b/)
    {
	$res->{'message'} = "There's a significantly newer version of LiveJournal for Windows available.";
    }
    unless ($LJ::EVERYONE_VALID)
    {
	if ($u->{'status'} eq "N") { $res->{'message'} = "You are currently not validated.  You may continue to use LiveJournal, but please validate your email address for continued use.  See the instructions that were mailed to you when you created your journal, or see $LJ::SITEROOT/support/ for more information."; }
	if ($u->{'status'} eq "T") { $res->{'message'} = "You need to validate your new email address.  Your old one was good, but since you've changed it, you need to re-validate the new one.  Visit the support area for more information."; }
    }
    if ($u->{'status'} eq "B") { $res->{'message'} = "You are currently using a bad email address.  All mail we try to send you is bouncing.  We require a valid email address for continued use.  Visit the support area for more information."; }

}

sub list_friendgroups
{
    my $dbs = shift;
    my $u = shift;
    
    my $res = [];
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT groupnum, groupname, sortorder, is_public ".
			    "FROM friendgroup WHERE userid=$u->{'userid'} ".
			    "ORDER BY sortorder");
    $sth->execute;
    while (my ($gid, $name, $sort, $public) = $sth->fetchrow_array) {
	push @$res, { 'id' => $gid,
		      'name' => $name,
		      'sortorder' => $sort,
		      'public' => $public };
    }
    $sth->finish;
    return $res;
}

sub list_usejournals
{
    my $dbs = shift;
    my $u = shift;
    
    my $res = [];

    my $dbr = $dbs->{'reader'};
    my $sth = $dbr->prepare("SELECT u.user FROM useridmap u, logaccess la WHERE la.ownerid=u.userid AND la.posterid=$u->{'userid'} ORDER BY u.user");
    $sth->execute;
    while (my $u = $sth->fetchrow_array) {
	push @$res, $u;
    }
    $sth->finish;
    return $res;
}

sub hash_menus
{
    my $dbs = shift;
    my $u = shift;
    my $user = $u->{'user'};

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
    
    unless ($u->{'paidfeatures'} eq "on" || 
	    $u->{'paidfeatures'} eq "paid") 
    {
	push @$menu, { 'text' => 'Upgrade your account',
		       'url' => "$LJ::SITEROOT/paidaccounts/", };
    }
    return $menu;
}

sub list_pickws
{
    my $dbs = shift;
    my $u = shift;

    my $dbr = $dbs->{'reader'};
    my $res = [];

    my $sth = $dbr->prepare("SELECT k.keyword FROM userpicmap m, keywords k ".
			    "WHERE m.userid=$u->{'userid'} AND m.kwid=k.kwid ".
			    "ORDER BY k.keyword");
    $sth->execute;
    while ($_ = $sth->fetchrow_array) {
	s/[\n\r\0]//g;  # used to be a bug that allowed these characters to get in.
	push @$res, $_;
    }
    $sth->finish;
    return $res;
}

sub list_moods
{
    my $dbs = shift;
    my $mood_max = int(shift);

    LJ::load_moods($dbs);

    my $res = [];    
    return $res unless ($mood_max < $LJ::CACHED_MOOD_MAX);

    for (my $id = $mood_max+1; $id <= $LJ::CACHED_MOOD_MAX; $id++) {
	next unless defined $LJ::CACHE_MOODS{$id};
	my $mood = $LJ::CACHE_MOODS{$id};
	push @$res, { 'id' => $id, 
		      'name' => $mood->{'name'},
		      'parent' => $mood->{'parent'} };
    }
    
    return $res;
}

sub check_altusage
{
    my ($dbs, $req, $err, $flags) = @_;

    my $alt = $req->{'usejournal'};
    my $u = $flags->{'u'};
    $flags->{'ownerid'} = $u->{'userid'};

    # all good if not using an alt journal
    return 1 unless $alt;

    # complain if the username is invalid
    return fail($err,203) unless LJ::canonical_username($alt);
   
    my $info = {};
    if (LJ::can_use_journal($dbs, $u->{'userid'}, $req->{'usejournal'}, $info)) {
	$flags->{'ownerid'} = $info->{'ownerid'};
	return 1;
    }

    # not allowed to access it
    return fail($err,300);
}

sub authenticate
{
    my ($dbs, $req, $err, $flags) = @_;

    my $username = $req->{'username'};
    return fail($err,200) unless $username;
    return fail($err,100) unless LJ::canonical_username($username);

    my $u = $flags->{'u'};
    unless ($u) {
	my $dbr = $dbs->{'reader'};
	my $quser = $dbr->quote($username);
	my $sth = $dbr->prepare("SELECT user, userid, journaltype, name, ".
				"paidfeatures, password, status, statusvis, ".
				"track FROM user WHERE user=$quser");
	$sth->execute;
	$u = $sth->fetchrow_hashref;
    }

    return fail($err,100) unless $u;
    return fail($err,101) unless ($flags->{'nopassword'} || 
				  $flags->{'noauth'} || 
  				  LJ::auth_okay($username,
						$req->{'password'},
						$req->{'hpassword'},
						$u->{'password'}));
    # remember the user record for later.
    $flags->{'u'} = $u;
    return 1;
}

sub fail
{
    my $err = shift;
    my $code = shift;
    $$err = $code;
    return undef;
}

#### Old interface (flat key/values) -- wrapper aruond LJ::Protocol
package LJ;

sub do_request
{
    # get the request and response hash refs
    my ($db_arg, $req, $res, $flags) = @_;

    # initialize some stuff
    my $dbs = LJ::make_dbs_from_arg($db_arg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    %{$res} = ();                      # clear the given response hash

    my ($user, $userid, $journaltype, $name, $paidfeatures, $correctpassword, $status, $statusvis, $track, $sth);
    $user = &trim(lc($req->{'user'}));
    my $quser = $dbh->quote($user);


    # check for an alive database connection
    unless ($dbh) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Server error: cannot connect to database.";
        return;
    }

    # did they send a mode?
    unless ($req->{'mode'}) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No mode specified.";
        return;
    }
    
    unless ($user) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No username sent.";
        return;
    }

    ### see if the server's under maintenance now
    if ($LJ::SERVER_DOWN) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = $LJ::SERVER_DOWN_MESSAGE;
        return;
    }

    ## dispatch wrappers
    if ($req->{'mode'} eq "login") {
	return login($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriendgroups") {
	return getfriendgroups($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriends") {
	return getfriends($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "friendof") {
	return friendof($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "checkfriends") {
	return checkfriends($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getdaycounts") {
	return getdaycounts($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "postevent") {
	return postevent($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "syncitems") {
	return syncitems($dbs, $req, $res, $flags);
    }

    ### OLD CODE FOLLOWS:

    # authenticate user
    unless ($flags->{'noauth'}) # && $req->{'mode'} ne "login")
    {
        $sth = $dbr->prepare("SELECT user, userid, journaltype, name, paidfeatures, password, status, statusvis, track FROM user WHERE user=$quser");
        $sth->execute;
        if ($dbr->err)
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "Server database error: " . $dbr->errstr;
	  return;
        }
        ($user, $userid, $journaltype, $name, $paidfeatures, $correctpassword, $status, $statusvis, $track) = $sth->fetchrow_array;

        if ($user eq "")
        {
	  $res->{'success'} = "FAIL";
	  $res->{'errmsg'} = "User error: Invalid Username";
	  return;
        }
        unless ($flags->{'nopassword'} || 
	        LJ::auth_okay($user, 
			      $req->{'password'}, 
			      $req->{'hpassword'},
			      $correctpassword))
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
	    $userid = LJ::get_userid($dbr, $user);
	}
    }

    $userid += 0;
    
    # setup the user object manually since the above stuff is old
    my $u = { 'user' => $user, 'userid' => $userid };

    ################################ AUTHENTICATED NOW ################################

 
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
	$sth = $dbr->prepare("SELECT groupnum FROM friendgroup WHERE userid=$userid");
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

		    my $friendid = LJ::get_userid($dbh, $friend);
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
		    $sth = $dbr->prepare("SELECT itemid FROM logsec WHERE ownerid=$userid AND allowmask & (1 << $bit)");
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
    
    ####
    #### MODE: editfriends
    ####
    if ($req->{'mode'} eq "editfriends")
    {
	## first, figure out who the current friends are to save us work later
	my %curfriend;
	my $friend_count = 0;
        $sth = $dbh->prepare("SELECT u.user FROM useridmap u, friends f WHERE u.userid=f.friendid AND f.userid=$userid");
        $sth->execute;
	while (my ($friend) = $sth->fetchrow_array) {
	    $curfriend{$friend} = 1;
	    $friend_count++;
	}

        # perform the deletions
      DELETEFRIEND:
        foreach (keys %{$req})
        {
	    if (/^editfriend_delete_(\w+)/) 
	    {
		my $deluser = LJ::canonical_username($1);
		next DELETEFRIEND unless ($curfriend{$deluser});

		my $qfriend = $dbh->quote($deluser);
		my $friendid = LJ::get_userid($dbh, $deluser);

		## delete from friends table
		$sth = $dbh->prepare("DELETE FROM friends WHERE userid=$userid AND friendid=$friendid");
		$sth->execute;

		$friend_count--;
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
		my $raw = $req->{"editfriend_add_${n}_user"};
		my $name = LJ::canonical_username($raw);
		next ADDFRIEND unless ($raw);
		unless ($name) {
		    $error_flag = 1;
		    next ADDFRIEND;
		}
		
		if (! $curfriend{$name}) {
		    $friend_count++;
		}

		if ($friend_count > LJ::get_limit("friends", $paidfeatures, 1500)) {
		    $error_flag = 1;
		    next ADDFRIEND;
		}

		my $fg = $req->{"editfriend_add_${n}_fg"} || "#000000";
		my $bg = $req->{"editfriend_add_${n}_bg"} || "#FFFFFF"; 
		if ($fg !~ /^\#[0-9A-F]{6,6}$/i || $bg !~ /^\#[0-9A-F]{6,6}$/i)
		{
		    $res->{'success'} = "FAIL";
		    $res->{'errmsg'} = "Client error: Invalid color values";
		    return;
		}

		my $row = LJ::load_user($dbs, $name);
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
		    my $sth = $dbh->prepare("SELECT groupmask FROM friends WHERE userid=$userid AND friendid=$friendid");
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
	  $res->{'errmsg'} = "Client error: There was an error adding one or more of the users you selected as friends.";
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
	    if (&can_use_journal($dbs, $posterid, $req->{'usejournal'}, $info)) {
		$ownerid = $info->{'ownerid'};
		$qowner = $dbh->quote($req->{'usejournal'});
	    } else {
                $res->{'errmsg'} = $info->{'errmsg'};
	    }
	}
        if ($res->{'errmsg'}) { $res->{'success'} = "FAIL"; return; }

	## why'd I introduce this redudant method into the protocol?
	if ($req->{'selecttype'} eq "one" && $req->{'itemid'} == -1) 
	{
	    $sth = $dbh->prepare("SELECT lastitemid FROM userusage ".
				 "WHERE userid=$ownerid");
	    $sth->execute;
	    my ($lastitemid) = $sth->fetchrow_array;		
	    
	    if ($lastitemid) {
		### we know the last one the entered!
		# Must be on master, since logtext is not replicated.
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
		'itemshow' => $LJ::MAX_HINTS_LASTN,
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
	    if (&can_use_journal($dbs, $posterid, $req->{'usejournal'}, $info)) {
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
		## deleting.
		if ($ownerid == $u->{'userid'}) {
		    ## community account can delete it (ick)
		    $allow = 1;
		} elsif (LJ::check_priv($dbr, $u, "sharedjournal", $req->{'usejournal'})) {
		    ## if user is a community maintainer they can delete it too (good)
		    $allow = 1;
		}
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
		while (my ($pid, $pname, $ptype) = $sth->fetchrow_array) {
		    if ($ptype eq "bool" && $props_byname{$pname} !~ /^[01]$/) {
			$res->{'errmsg'} = "Client error: Property \"$pname\" should be 0 or 1";
		    }
		    if ($ptype eq "num" && $props_byname{$pname} =~ /[^\d]/) {
			$res->{'errmsg'} = "Client error: Property \"$pname\" should be numeric";
		    }
		    $props{$pid} = $props_byname{$pname};
		    delete $props_byname{$pname};
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
		my $qsecurity = $dbh->quote($security);
		$sth = $dbh->prepare("UPDATE log SET eventtime=$qeventtime, year=$qyear, month=$qmonth, day=$qday, security=$qsecurity, allowmask=$qallowmask WHERE itemid=$qitemid");
		$sth->execute;
	    }

	    if ($security ne $oldevent->{'security'} ||
		$qallowmask != $oldevent->{'allowmask'})
	    {
		if ($security eq "public" || $security eq "private") {
		    $dbh->do("DELETE FROM logsec WHERE ownerid=$ownerid AND itemid=$qitemid");
		} else {
		    my $qsecurity = $dbh->quote($security);
		    $dbh->do("REPLACE INTO logsec (ownerid, itemid, allowmask) VALUES ($ownerid, $qitemid, $qallowmask)");		    
		}
	    }

	    if (Digest::MD5::md5_hex($event) ne $oldevent->{'md5event'} ||
		$req->{'subject'} ne $oldevent->{'subject'})
	    {
		my $qsubject = $dbh->quote($req->{'subject'});	    

		my @prefix = ("");
		if ($LJ::USE_RECENT_TABLES) { push @prefix, "recent_"; }
		foreach my $pfx (@prefix) {
		    $sth = $dbh->prepare("UPDATE ${pfx}logtext SET event=$qevent, subject=$qsubject WHERE itemid=$qitemid");
		    $sth->execute;
		}
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



    ### unknown mode!
    $res->{'success'} = "FAIL";
    $res->{'errmsg'} = "Client error: Unknown mode ($req->{'mode'})";
    return;
}

## flat wrapper
sub login
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("login", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    $res->{'name'} = $rs->{'fullname'};
    $res->{'message'} = $rs->{'message'} if $rs->{'message'};
    $res->{'fastserver'} = 1 if $rs->{'fastserver'};
    
    # shared journals
    my $access_count = 0;
    foreach my $user (@{$rs->{'usejournals'}}) {
	$access_count++;
	$res->{"access_${access_count}"} = $user;
    }
    if ($access_count) {
	$res->{"access_count"} = $access_count;
    }

    # friend groups
    populate_friend_groups($res, $rs->{'friendgroups'});
    
    ### picture keywords
    if (defined $req->{"getpickws"}) 
    {
	my $pickw_count = 0;
	foreach (@{$rs->{'pickws'}}) {
	    $pickw_count++;
	    $res->{"pickw_${pickw_count}"} = $_;
	}
	if ($pickw_count) {
	    $res->{"pickw_count"} = $pickw_count;
	}
    }
    
    ### report new moods that this client hasn't heard of, if they care
    if (defined $req->{"getmoods"}) {
	my $mood_count = 0;	
	foreach my $m (@{$rs->{'moods'}}) {
	    $mood_count++;
	    $res->{"mood_${mood_count}_id"} = $m->{'id'};
	    $res->{"mood_${mood_count}_name"} = $m->{'name'};
	}
	if ($mood_count) {
	    $res->{"mood_count"} = $mood_count;
	}
    }
    
    #### send web menus
    if ($req->{"getmenus"} == 1) {
	my $menu = $rs->{'menus'};
	my $menu_num = 0;
	populate_web_menu($res, $menu, \$menu_num);
    }
    
    return 1;
}

## flat wrapper
sub getfriendgroups
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("getfriendgroups", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }
    $res->{'success'} = "OK";
    populate_friend_groups($res, $rs->{'friendgroups'});
    
    return 1;
}

## flat wrapper
sub getfriends
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("getfriends", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    if ($req->{'includegroups'}) {
	populate_friend_groups($res, $rs->{'friendgroups'});
    }
    if ($req->{'includefriendof'}) {
	populate_friends($res, "friendof", $rs->{'friendofs'});
    }
    populate_friends($res, "friend", $rs->{'friends'});
    
    return 1;
}

## flat wrapper
sub friendof
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("friendof", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    populate_friends($res, "friendof", $rs->{'friendofs'});
    return 1;
}

## flat wrapper
sub checkfriends
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("checkfriends", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    $res->{'new'} = $rs->{'new'};
    $res->{'lastupdate'} = $rs->{'lastupdate'};
    $res->{'interval'} = $rs->{'interval'};
    return 1;
}

## flat wrapper
sub getdaycounts
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("getdaycounts", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    foreach my $d (@{ $rs->{'daycounts'} }) {
	$res->{$d->{'date'}} = $d->{'count'};
    }
    return 1;
}

## flat wrapper
sub syncitems
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    my $rs = LJ::Protocol::do_request("syncitems", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    $res->{'sync_total'} = $rs->{'total'};
    $res->{'sync_count'} = $rs->{'count'};
    
    my $ct = 0;
    foreach my $s (@{ $rs->{'syncitems'} }) {
	$ct++;
	foreach my $a (qw(item action time)) {
	    $res->{"sync_${ct}_$a"} = $s->{$a};
	}
    }
    return 1;
}

## flat wrapper
sub postevent
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    
    ## changes prop_* to props hashref
    foreach my $k (keys %$req) {
	next unless ($k =~ /^prop_(.+)/);
	$rq->{'props'}->{$1} = $req->{$k};	
    }

    my $rs = LJ::Protocol::do_request("postevent", $rq, \$err, $flags);
    unless ($rs) {
	$res->{'success'} = "FAIL";
	$res->{'errmsg'} = LJ::Protocol::error_message($err);
	return 0;
    }

    $res->{'success'} = "OK";
    $res->{'itemid'} = $rs->{'itemid'};
    return 1;
}


sub populate_friends
{
    my ($res, $pfx, $list) = @_;
    my $count = 0;
    foreach my $f (@$list)
    {
	$count++;
	$res->{"${pfx}_${count}_name"} = $f->{'fullname'};
	$res->{"${pfx}_${count}_user"} = $f->{'username'};
	$res->{"${pfx}_${count}_bg"} = $f->{'bgcolor'};
	$res->{"${pfx}_${count}_fg"} = $f->{'fgcolor'};
	if (defined $f->{'groupmask'}) {
	    $res->{"${pfx}_${count}_groupmask"} = $f->{'groupmask'};
	}
	if (defined $f->{'type'}) {
	    $res->{"${pfx}_${count}_type"} = $f->{'type'};
	}
    }
    $res->{"${pfx}_count"} = $count;    
}


sub upgrade_request
{
    my $r = shift;
    my $new = { %{ $r } };
    $new->{'username'} = $r->{'user'};

    # but don't delete $r->{'user'}, as it might be, say, %FORM,
    # that'll get reused in a later request in, say, update.bml after
    # the login before postevent.  whoops.

    return $new;
}

## given a $res hashref and friend group subtree (arrayref), flattens it
sub populate_friend_groups
{
    my ($res, $fr) = @_;

    my $maxnum = 0;
    foreach my $fg (@$fr)
    {
	my $num = $fg->{'id'};
	$res->{"frgrp_${num}_name"} = $fg->{'name'};
	$res->{"frgrp_${num}_sortorder"} = $fg->{'sortorder'};
	if ($fg->{'public'}) {
	    $res->{"frgrp_${num}_public"} = 1;
	}
	if ($num > $maxnum) { $maxnum = $num; }
    }
    $res->{'frgrp_maxnum'} = $maxnum;
}

## given a menu tree, flattens it into $res hashref
sub populate_web_menu 
{
    my ($res, $menu, $numref) = @_;
    my $mn = $$numref;  # menu number
    my $mi = 0;         # menu item
    foreach my $it (@$menu) {
	$mi++;
	$res->{"menu_${mn}_${mi}_text"} = $it->{'text'};
	if ($it->{'text'} eq "-") { next; }
	if ($it->{'sub'}) { 
	    $$numref++; 
	    $res->{"menu_${mn}_${mi}_sub"} = $$numref;
	    &populate_web_menu($res, $it->{'sub'}, $numref); 
	    next;
	    
	}
	$res->{"menu_${mn}_${mi}_url"} = $it->{'url'};
    }
    $res->{"menu_${mn}_count"} = $mi;
}


1;
