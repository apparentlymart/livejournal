#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/ljlib.pl, cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/cleanhtml.pl
# </LJDEP>

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";

# the creator for the 'lastn' view:
sub create_view_lastn
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    my $user = $u->{'user'};

    LJ::load_user_props($dbs, $u, "opt_blockrobots", "url", "urlname");

    my %FORM = ();
    &get_form_data(\%FORM);

    if ($opts->{'args'}) {
	$opts->{'badargs'} = 1;
	return 1;
    }

    my %lastn_page = ();
    $lastn_page{'name'} = LJ::ehtml($u->{'name'});
    $lastn_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $lastn_page{'username'} = $user;
    $lastn_page{'numitems'} = $vars->{'LASTN_OPT_ITEMS'} || 20;

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $lastn_page{'urlfriends'} = "$journalbase/friends";
    $lastn_page{'urlcalendar'} = "$journalbase/calendar";

    my %userpics;
    if ($u->{'defaultpicid'}) {
	my $picid = $u->{'defaultpicid'};
	LJ::load_userpics($dbs, \%userpics, [ $picid ]);
	$lastn_page{'userpic'} = 
	    &fill_var_props($vars, 'LASTN_USERPIC', {
		"src" => "$LJ::SITEROOT/userpic/$picid",
		"width" => $userpics{$picid}->{'width'},
		"height" => $userpics{$picid}->{'height'},
	    });
    }

    if ($u->{'url'} =~ m!^http://!) {
	$lastn_page{'website'} =
	    &fill_var_props($vars, 'LASTN_WEBSITE', {
		"url" => LJ::ehtml($u->{'url'}),
		"name" => LJ::ehtml($u->{'urlname'} || "My Website"),
	    });
    }

    $lastn_page{'events'} = "";
    if ($u->{'opt_blockrobots'}) {
	$lastn_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($FORM{'skip'}) {
	# if followed a skip link back, prevent it from going back further
	$lastn_page{'head'} = "<meta name=\"robots\" content=\"noindex,nofollow\">\n";
    }
    $lastn_page{'head'} .= 
	$vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    $events = \$lastn_page{'events'};
    
    my $quser = $dbh->quote($user);
    my $qremoteuser = $dbh->quote($remote->{'user'});
    my $qremoteid = $dbh->quote($remote->{'userid'});
    
    my $itemshow = $vars->{'LASTN_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $FORM{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    ## load the itemids
    my @itemids = LJ::get_recent_itemids($dbs, {
	'view' => 'lastn',
	'userid' => $u->{'userid'},
	'remoteid' => $remote->{'userid'},
	'itemshow' => $itemshow,
	'skip' => $skip,
    });
    
    my $order_by = "eventtime DESC, logtime DESC";
    if ($u->{'journaltype'} eq "C") {
	## communties sort by time posted
	$order_by = "logtime DESC, eventtime DESC";
    }

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props($dbs, \@itemids, \%logprops);
    LJ::load_moods($dbs);

    my $logtext = LJ::get_logtext($dbs, @itemids);

    # load the log items
    my $itemid_in = join(", ", map { $_+0; } @itemids);
    $sth = $dbr->prepare("SELECT posterid, itemid, security, DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H\") AS 'alldatepart', replycount FROM log WHERE itemid IN ($itemid_in) ORDER BY $order_by");
    $sth->execute;

    my $lastday = -1;
    my $lastmonth = -1;
    my $lastyear = -1;
    my $eventnum = 0;

    my %altposter_picid = ();  # map ALT_POSTER userids to defaultpicids

    while (my ($posterid, $itemid, $security, $alldatepart, $replycount) = $sth->fetchrow_array)
    {
	my $subject = $logtext->{$itemid}->[0];
	my $event = $logtext->{$itemid}->[1];

        my @dateparts = split(/ /, $alldatepart);
        my %lastn_date_format = (
			   'dayshort' => $dateparts[0],
			   'daylong' => $dateparts[1],
			   'monshort' => $dateparts[2],
			   'monlong' => $dateparts[3],
			   'yy' => $dateparts[4],
			   'yyyy' => $dateparts[5],
			   'm' => $dateparts[6],
			   'mm' => $dateparts[7],
			   'd' => $dateparts[8],
			   'dd' => $dateparts[9],
			   'dth' => $dateparts[10],
			   'ap' => substr(lc($dateparts[11]),0,1),
			   'AP' => substr(uc($dateparts[11]),0,1),
			   'ampm' => lc($dateparts[11]),
			   'AMPM' => $dateparts[11],
			   'min' => $dateparts[12],
			   '12h' => $dateparts[13],
			   '12hh' => $dateparts[14],
			   '24h' => $dateparts[15],
			   '24hh' => $dateparts[16],
				 );

        if ($lastday != $lastn_date_format{'d'} ||
	    $lastmonth != $lastn_date_format{'m'} ||
	    $lastyear != $lastn_date_format{'yyyy'})
        {
	  my %lastn_new_day = ();
	  foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
	  {
	      $lastn_new_day{$_} = $lastn_date_format{$_};
	  }
	  unless ($lastday==-1) {
	      $$events .= &fill_var_props($vars, 'LASTN_END_DAY', {});
	  }
	  $$events .= &fill_var_props($vars, 'LASTN_NEW_DAY', \%lastn_new_day);

	  $lastday = $lastn_date_format{'d'};
	  $lastmonth = $lastn_date_format{'m'};
	  $lastyear = $lastn_date_format{'yyyy'};
        }

        my %lastn_event = ();
        $eventnum++;
        $lastn_event{'eventnum'} = $eventnum;
        $lastn_event{'itemid'} = $itemid;
        $lastn_event{'datetime'} = &fill_var_props($vars, 'LASTN_DATE_FORMAT', \%lastn_date_format);
	if ($subject) {
	    LJ::CleanHTML::clean_subject(\$subject);
	    $lastn_event{'subject'} = &fill_var_props($vars, 'LASTN_SUBJECT', { 
		"subject" => $subject,
	    });
	}

	LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
					       'cuturl' => LJ::item_link($u, $itemid), });
	LJ::expand_embedded($dbs, $itemid, $remote, \$event);
        $lastn_event{'event'} = $event;

	if ($u->{'opt_showtalklinks'} eq "Y" && 
	    ! $logprops{$itemid}->{'opt_nocomments'}
	    ) {
	    $lastn_event{'talklinks'} = &fill_var_props($vars, 'LASTN_TALK_LINKS', {
		'itemid' => $itemid,
		'urlpost' => "$LJ::SITEROOT/talkpost.bml?itemid=$itemid",
		'readlink' => $replycount ? &fill_var_props($vars, 'LASTN_TALK_READLINK', {
		    'urlread' => "$LJ::SITEROOT/talkread.bml?itemid=$itemid&amp;nc=$replycount",
		    'messagecount' => $replycount,
		    'mc-plural-s' => $replycount == 1 ? "" : "s",
		    'mc-plural-es' => $replycount == 1 ? "" : "es",
		    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
		}) : "",
	    });
	}

	## current stuff
	&prepare_currents({ 'props' => \%logprops, 
			    'itemid' => $itemid, 
			    'vars' => $vars, 
			    'prefix' => "LASTN",
			    'event' => \%lastn_event,
			    'user' => $u,
			});

	if ($u->{'userid'} != $posterid) 
	{
	    my %lastn_altposter = ();

	    my $poster = LJ::get_username($dbs, $posterid);
	    $lastn_altposter{'poster'} = $poster;
	    $lastn_altposter{'owner'} = $user;
	    
	    my $picid = 0;
	    if ($logprops{$itemid}->{'picture_keyword'}) {
		my $qkw = $dbr->quote($logprops{$itemid}->{'picture_keyword'});
		my $sth = $dbr->prepare("SELECT m.picid FROM userpicmap m, keywords k WHERE m.userid=$posterid AND m.kwid=k.kwid AND k.keyword=$qkw");
		$sth->execute;
		($picid) = $sth->fetchrow_array;
	    } 
	    unless ($picid) {
		if (exists $altposter_picid{$posterid}) {
		    $picid = $altposter_picid{$posterid};
		} else {
		    my $st2 = $dbr->prepare("SELECT defaultpicid FROM user WHERE userid=$posterid");
		    $st2->execute;
		    ($picid) = $st2->fetchrow_array;
		    $altposter_picid{$posterid} = $picid;
		}
	    }

	    if ($picid) 
	    {
		my $pic = {};
		LJ::load_userpics($dbs, $pic, [ $picid ]);
		$lastn_altposter{'pic'} = &fill_var_props($vars, 'LASTN_ALTPOSTER_PIC', {
		    "src" => "$LJ::SITEROOT/userpic/$picid",
		    "width" => $pic->{$picid}->{'width'},
		    "height" => $pic->{$picid}->{'height'},
		});
	    }
	    $lastn_event{'altposter'} = 
		&fill_var_props($vars, 'LASTN_ALTPOSTER', \%lastn_altposter);
	}

	my $var = 'LASTN_EVENT';
	if ($security eq "private" && 
	    $vars->{'LASTN_EVENT_PRIVATE'}) { $var = 'LASTN_EVENT_PRIVATE'; }
	if ($security eq "usemask" && 
	    $vars->{'LASTN_EVENT_PROTECTED'}) { $var = 'LASTN_EVENT_PROTECTED'; }
        $$events .= &fill_var_props($vars, $var, \%lastn_event);
    } # end huge while loop

    $$events .= &fill_var_props($vars, 'LASTN_END_DAY', {});

    if ($skip) {
	$lastn_page{'range'} = 
	    &fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
		"numitems" => $eventnum,
		"skip" => $skip,
	    });
    } else {
	$lastn_page{'range'} = 
	    &fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
		"numitems" => $eventnum,
	    });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    ### if we've skipped down, then we can skip back up

    if ($skip) {
	$skip_f = 1;
	my $newskip = $skip - $itemshow;
	if ($newskip <= 0) { $newskip = ""; }
	else { $newskip = "?skip=$newskip"; }

	$skiplinks{'skipforward'} = 
	    &fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
		"numitems" => $itemshow,
		"url" => "$journalbase/$newskip",
	    });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown 
    ## on the page, but who cares about that)

    unless ($eventnum != $itemshow) {
	$skip_b = 1;

	if ($skip==$maxskip) {
	    $skiplinks{'skipbackward'} = 
		&fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
		    "numitems" => "Day",
		    "url" => "$journalbase/day/" . sprintf("%04d/%02d/%02d", $lastyear, $lastmonth, $lastday),
		});
	} else {
	    my $newskip = $skip + $itemshow;
	    $newskip = "?skip=$newskip";
	    $skiplinks{'skipbackward'} = 
		&fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
		    "numitems" => $itemshow,
		    "url" => "$journalbase/$newskip",
		});
	}
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
	$skiplinks{'skipspacer'} = $vars->{'LASTN_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
	$lastn_page{'skiplinks'} = 
	    &fill_var_props($vars, 'LASTN_SKIP_LINKS', \%skiplinks);
    }

    $$ret = &fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $user = $u->{'user'};

    my $REFRESH_TIME = 20;
    $$ret = "";

    my %FORM = ();
    &get_form_data(\%FORM);

    if ($FORM{'mode'} eq "live") {
	$$ret .= "<html><head><title>${user}'s friends: live!</title></head>\n";
	$$ret .= "<frameset rows=\"100%,0%\" border=0>\n";
	$$ret .= "  <frame name=livetop src=\"friends?mode=framed\">\n";
	$$ret .= "  <frame name=livebottom src=\"friends?mode=livecond&amp;lastitemid=0\">\n";
	$$ret .= "</frameset></html>\n";
	return 1;
    }

    LJ::load_user_props($dbs, $u, "opt_usesharedpic", "url", "urlname");

    my %friends_page = ();
    $friends_page{'name'} = LJ::ehtml($u->{'name'});
    $friends_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $user;
    $friends_page{'numitems'} = $vars->{'FRIENDS_OPT_ITEMS'} || 20;

    ## never have spiders index friends pages (change too much, and some 
    ## people might not want to be indexed)
    $friends_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    $friends_page{'head'} .= 
	$vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'FRIENDS_HEAD'};

    if ($u->{'url'} =~ m!^http://!) {
	$friends_page{'website'} =
	    &fill_var_props($vars, 'FRIENDS_WEBSITE', {
		"url" => LJ::ehtml($u->{'url'}),
		"name" => LJ::ehtml($u->{'urlname'} || "My Website"),
	    });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    $friends_page{'urlcalendar'} = "$journalbase/calendar";
    $friends_page{'urllastn'} = "$journalbase/";

    $friends_page{'events'} = "";

    my $quser = $dbr->quote($user);
    my $qremoteuser = $dbr->quote($remote->{'user'});
    my $qremoteid = $dbr->quote($remote->{'userid'});

    my $itemshow = $vars->{'FRIENDS_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $FORM{'skip'}+0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;

    my %owners;
    my $filter;
    if (defined $FORM{'filter'}) {
	$filter = $FORM{'filter'}; 
    } else {
	my $group;
	if ($opts->{'args'}) {
	    $group = $opts->{'args'};
	    $group =~ s!^/!!;
	    $group =~ s!\?.*!!;
	    if ($group) { $group = &durl($group); }
	}
	$group ||= "Default View";
	my $qgroup = $dbr->quote($group);
	$sth = $dbr->prepare("SELECT groupnum FROM friendgroup WHERE userid=$u->{'userid'} AND groupname=$qgroup");
	$sth->execute;
	my ($bit) = $sth->fetchrow_array;
	if ($bit) { $filter = (1 << $bit); }
    }


    if ($FORM{'mode'} eq "livecond") 
    {
	## load the itemids
	my @itemids = LJ::get_friend_itemids($dbs, {
	    'view' => 'friends',
	    'userid' => $u->{'userid'},
	    'remoteid' => $remote->{'userid'},
	    'itemshow' => 1,
	    'skip' => 0,
	    'filter' => $filter,
	});
	my $first = $itemids[0];

	$$ret .= "time = " . scalar(time()) . "<br>";
	$opts->{'headers'}->{'Refresh'} = "$REFRESH_TIME;URL=$LJ::SITEROOT/users/$user/friends?mode=livecond&amp;lastitemid=$first";
	if ($FORM{'lastitemid'} == $itemids[0]) {
	    $$ret .= "nothing new!";
	} else {
	    if ($FORM{'lastitemid'}) {
		$$ret .= "<b>New stuff!</b>\n";
		$$ret .= "<script language=\"JavaScript\">\n";
		$$ret .= "window.parent.livetop.location.reload(true);\n";	    
		$$ret .= "</script>\n";
		$opts->{'trusted_html'} = 1;
	    } else {
		$$ret .= "Friends Live! started.";
	    }
	}
	return 1;
    }
    
    ## load the itemids
    my @itemids = LJ::get_friend_itemids($dbs, {
        'view' => 'friends',
        'userid' => $u->{'userid'},
        'remoteid' => $remote->{'userid'},
        'itemshow' => $itemshow,
        'skip' => $skip,
	'filter' => $filter,
	'owners' => \%owners,
    });

    my $ownersin = join(",", keys %owners);

    my %friends = ();
    $sth = $dbr->prepare("SELECT u.user, u.userid, f.fgcolor, f.bgcolor, u.name, u.defaultpicid, u.opt_showtalklinks, u.moodthemeid, u.statusvis FROM friends f, user u WHERE u.userid=f.friendid AND f.userid=$u->{'userid'} AND f.friendid IN ($ownersin)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
	next unless ($_->{'statusvis'} eq "V");  # ignore suspended/deleted users.
	$friends{$_->{'userid'}} = $_;
    }

    unless (%friends)
    {
        $friends_page{'events'} = &fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
	  "name" => LJ::ehtml($u->{'name'}),
	  "name-\'s" => ($u->{'name'} =~ /s$/i) ? "'" : "'s",
	  "username" => $user,
        });

	$$ret .= "<BASE TARGET=_top>" if ($FORM{'mode'} eq "framed");
	$$ret .= &fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
	return 1;
    }

    $friendsin = join(", ", map { $dbr->quote($_) } keys %friends);
    
    ### load the log properties
    my %logprops = ();
    LJ::load_log_props($dbs, \@itemids, \%logprops);
    LJ::load_moods($dbs);

    # load the pictures for the user
    my %userpics;
    my @picids = map { $friends{$_}->{'defaultpicid'} } keys %friends;
    LJ::load_userpics($dbs, \%userpics, [ @picids ]);

    # load the text of the entries
    my $logtext = LJ::get_logtext($dbs, @itemids);
  
    # load the log items
    my $itemid_in = join(", ", map { $_+0; } @itemids);
    $sth = $dbr->prepare("SELECT itemid, security, ownerid, posterid, DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H\") AS 'alldatepart', replycount FROM log WHERE itemid IN ($itemid_in) ORDER BY logtime DESC");
    $sth->execute;

    ## suck it all into memory to free the db.
    my @log_rows = ();
    while (my @logrow = $sth->fetchrow_array) {
	push @log_rows, [ @logrow ];
    }

    my %posterdefpic;  # map altposter userids -> default picture ids
    
    my %friends_events = ();
    my $events = \$friends_events{'events'};
    
    my $lastday = -1;
    my $eventnum = 0;
    while (@log_rows)
    {
	my $logrow = shift @log_rows;
	my ($itemid, $security, $friendid, $posterid, $alldatepart, $replycount) = @{$logrow};
	
	my $subject = $logtext->{$itemid}->[0];
	my $event = $logtext->{$itemid}->[1];

	my ($friend, $poster);
	$friend = LJ::get_username($dbs, $friendid);
	$poster = LJ::get_username($dbs, $posterid);
	
	$eventnum++;
	my @dateparts = split(/ /, $alldatepart);
	my %friends_date_format = (
				   'dayshort' => $dateparts[0],
				   'daylong' => $dateparts[1],
				   'monshort' => $dateparts[2],
				   'monlong' => $dateparts[3],
				   'yy' => $dateparts[4],
				   'yyyy' => $dateparts[5],
				   'm' => $dateparts[6],
				   'mm' => $dateparts[7],
				   'd' => $dateparts[8],
				   'dd' => $dateparts[9],
				   'dth' => $dateparts[10],
				   'ap' => substr(lc($dateparts[11]),0,1),
				   'AP' => substr(uc($dateparts[11]),0,1),
				   'ampm' => lc($dateparts[11]),
				   'AMPM' => $dateparts[11],
				   'min' => $dateparts[12],
				   '12h' => $dateparts[13],
				   '12hh' => $dateparts[14],
				   '24h' => $dateparts[15],
				   '24hh' => $dateparts[16],
				   );
	if ($lastday != $friends_date_format{'d'})
	{
	    my %friends_new_day = ();
	    foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
	    {
		$friends_new_day{$_} = $friends_date_format{$_};
	    }
	    unless ($lastday==-1) {
		$$events .= &fill_var_props($vars, 'FRIENDS_END_DAY', {});
	    }
	    $$events .= &fill_var_props($vars, 'FRIENDS_NEW_DAY', \%friends_new_day);
	    $lastday = $friends_date_format{'d'};
	}
	
	my %friends_event = ();
	$friends_event{'itemid'} = $itemid;
	$friends_event{'datetime'} = &fill_var_props($vars, 'FRIENDS_DATE_FORMAT', \%friends_date_format);
	if ($subject) {
	    LJ::CleanHTML::clean_subject(\$subject);
	    $friends_event{'subject'} = &fill_var_props($vars, 'FRIENDS_SUBJECT', { 
		"subject" => $subject,
	    });
	} else {
	    $friends_event{'subject'} = &fill_var_props($vars, 'FRIENDS_NO_SUBJECT', { 
		"friend" => $friend,
		"name" => $friends{$friendid}->{'name'},
	    });
	}
	
	LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
					       'cuturl' => LJ::item_link($u, $itemid), });
	LJ::expand_embedded($dbs, $itemid, $remote, \$event);
	$friends_event{'event'} = $event;
	
        # do the picture
	{
	    my $picid = $friends{$friendid}->{'defaultpicid'};  # this could be the shared journal pic
	    if ($friendid != $posterid && ! $u->{'opt_usesharedpic'}) {
		unless (defined $posterdefpic{$posterid}) {
		    my $pdpic = 0;
		    my $sth = $dbr->prepare("SELECT defaultpicid FROM user WHERE userid=$posterid");
		    $sth->execute;
		    ($pdpic) = $sth->fetchrow_array;
		    $posterdefpic{$posterid} = $pdpic ? $pdpic : 0;
		}
		if ($posterdefpic{$posterid}) { 
		    $picid = $posterdefpic{$posterid}; 
		    LJ::load_userpics($dbs, \%userpics, [ $picid ]);
		}
	    }
	    if ($logprops{$itemid}->{'picture_keyword'} && 
		(! $u->{'opt_usesharedpic'} || ($posterid == $friendid))) 
	    {
		my $qkw = $dbh->quote($logprops{$itemid}->{'picture_keyword'});
		my $sth = $dbh->prepare("SELECT m.picid FROM userpicmap m, keywords k WHERE m.userid=$posterid AND m.kwid=k.kwid AND k.keyword=$qkw");
		$sth->execute;
		my ($alt_picid) = $sth->fetchrow_array;
		if ($alt_picid) {
		    LJ::load_userpics($dbs, \%userpics, [ $alt_picid ]);
		    $picid = $alt_picid;
		}
	    }
	    if ($picid) {
		$friends_event{'friendpic'} = 
		    &fill_var_props($vars, 'FRIENDS_FRIENDPIC', {
			"src" => "$LJ::SITEROOT/userpic/$picid",
			"width" => $userpics{$picid}->{'width'},
			"height" => $userpics{$picid}->{'height'},
		    });
	    }
	}
	
	if ($friend ne $poster) {
	    $friends_event{'altposter'} = 
		&fill_var_props($vars, 'FRIENDS_ALTPOSTER', {
		    "poster" => $poster,
		    "owner" => $friend,
		    "fgcolor" => $friends{$friendid}->{'fgcolor'} || "#000000",
		    "bgcolor" => $friends{$friendid}->{'bgcolor'} || "#ffffff",
		});
	}

	# friends view specific:
	$friends_event{'user'} = $friend;
	$friends_event{'fgcolor'} = $friends{$friendid}->{'fgcolor'} || "#000000";
	$friends_event{'bgcolor'} = $friends{$friendid}->{'bgcolor'} || "#ffffff";
	
	if ($friends{$friendid}->{'opt_showtalklinks'} eq "Y" &&
	    ! $logprops{$itemid}->{'opt_nocomments'}
	    ) {
	    $friends_event{'talklinks'} = &fill_var_props($vars, 'FRIENDS_TALK_LINKS', {
		'itemid' => $itemid,
		'urlpost' => "$LJ::SITEROOT/talkpost.bml?itemid=$itemid",
		'readlink' => $replycount ? &fill_var_props($vars, 'FRIENDS_TALK_READLINK', {
		    'urlread' => "$LJ::SITEROOT/talkread.bml?itemid=$itemid&amp;nc=$replycount",
		    'messagecount' => $replycount,
		    'mc-plural-s' => $replycount==1 ? "" : "s",
		    'mc-plural-es' => $replycount == 1 ? "" : "es",
		    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
		}) : "",
	    });
	}

	## current stuff
	&prepare_currents({ 'props' => \%logprops, 
			    'itemid' => $itemid, 
			    'vars' => $vars, 
			    'prefix' => "FRIENDS",
			    'event' => \%friends_event,
			    'user' => ($u->{'opt_forcemoodtheme'} eq "Y" ? $u : $friends{$friendid}),
			});

	my $var = 'FRIENDS_EVENT';
	if ($security eq "private" && 
	    $vars->{'FRIENDS_EVENT_PRIVATE'}) { $var = 'FRIENDS_EVENT_PRIVATE'; }
	if ($security eq "usemask" && 
	    $vars->{'FRIENDS_EVENT_PROTECTED'}) { $var = 'FRIENDS_EVENT_PROTECTED'; }
	
	$$events .= &fill_var_props($vars, $var, \%friends_event);
    } # end while

    $$events .= &fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = &fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    ### set the range property (what entries are we looking at)

    if ($skip) {
	$friends_page{'range'} = 
	    &fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
		"numitems" => $eventnum,
		"skip" => $skip,
	    });
    } else {
	$friends_page{'range'} = 
	    &fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
		"numitems" => $eventnum,
	    });
    }

    ### if we've skipped down, then we can skip back up

    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    if ($skip) {
	$skip_f = 1;
	my %linkvars;
	if ($filter) { $linkvars{'filter'} = $filter; }

	my $newskip = $skip - $itemshow;
	if ($newskip > 0) { $linkvars{'skip'} = $newskip; }

	$skiplinks{'skipforward'} = 
	    &fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
		"numitems" => $itemshow,
		"url" => &make_link("$journalbase/friends", \%linkvars),
	    });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown 
    ## on the page, but who cares about that)

    unless ($eventnum != $itemshow || $skip == $maxskip) {
	$skip_b = 1;
	my %linkvars;
	if ($filter) { $linkvars{'filter'} = $filter; }

	my $newskip = $skip + $itemshow;
	$linkvars{'skip'} = $newskip;

	$skiplinks{'skipbackward'} = 
	    &fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
		"numitems" => $itemshow,
		"url" => &make_link("$journalbase/friends", \%linkvars),
	    });
    }

    ### if they're both on, show a spacer
    if ($skip_f && $skip_b) {
	$skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
	$friends_page{'skiplinks'} = 
	    &fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }
    
    $$ret .= "<BASE TARGET=_top>" if ($FORM{'mode'} eq "framed");
    $$ret .= &fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

    return 1;
}

# the creator for the 'calendar' view:
sub create_view_calendar
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    my $user = $u->{'user'};
    LJ::load_user_props($dbs, $u, "opt_blockrobots", "url", "urlname");
    my %FORM = ();
    &get_form_data(\%FORM);

    my %calendar_page = ();
    $calendar_page{'name'} = LJ::ehtml($u->{'name'});
    $calendar_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    if ($u->{'opt_blockrobots'}) {
	$calendar_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    $calendar_page{'head'} .=
	$vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};
    
    $calendar_page{'months'} = "";

    if ($u->{'url'} =~ m!^http://!) {
	$calendar_page{'website'} =
	    &fill_var_props($vars, 'CALENDAR_WEBSITE', {
		"url" => LJ::ehtml($u->{'url'}),
		"name" => LJ::ehtml($u->{'urlname'} || "My Website"),
	    });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    
    $calendar_page{'urlfriends'} = "$journalbase/friends";
    $calendar_page{'urllastn'} = "$journalbase/";

    my $months = \$calendar_page{'months'};

    my $quser = $dbr->quote($user);
    my $quserid = $dbr->quote($u->{'userid'});
    my $maxyear = 0;

    my $sth = $dbr->prepare("SELECT year, month, day, DAYOFWEEK(CONCAT(year, \"-\", month, \"-\", day)) AS 'dayweek', COUNT(*) AS 'count' FROM log WHERE ownerid=$quserid GROUP BY year, month, day, dayweek");
    $sth->execute;

    my (%count, %dayweek, $year, $month, $day, $dayweek, $count);
    while (($year, $month, $day, $dayweek, $count) = $sth->fetchrow_array)
    {
        $count{$year}->{$month}->{$day} = $count;
        $dayweek{$year}->{$month}->{$day} = $dayweek;
	if ($year > $maxyear) { $maxyear = $year; }
    }

    my @allyears = sort { $b <=> $a } keys %count;
    if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @allyears = reverse @allyears; }

    my @years = ();
    my $dispyear = $FORM{'year'};  # old form was /users/<user>/calendar?year=1999

    # but the new form is purtier:  */calendar/2001
    unless ($dispyear) {
	if ($opts->{'args'} =~ m!^/(\d\d\d\d)/?\b!) {
	    $dispyear = $1;
	}
    }

    # else... default to the year they last posted.
    $dispyear ||= $maxyear;  

    # we used to show multiple years.  now we only show one at a time:  (hence the @years confusion)
    if ($dispyear) { push @years, $dispyear; }  

    if (scalar(@allyears) > 1) {
	my $yearlinks = "";
	foreach my $year (@allyears) {
	    my $yy = sprintf("%02d", $year % 100);
	    my $url = "$journalbase/calendar/$year";
	    if ($year != $dispyear) { 
		$yearlinks .= &fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
		    "url" => $url, "yyyy" => $year, "yy" => $yy });
	    } else {
		$yearlinks .= &fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
		    "yyyy" => $year, "yy" => $yy });
	    }
	}
	$calendar_page{'yearlinks'} = 
	    &fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    foreach $year (@years)
    {
        $$months .= &fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
	  'yyyy' => $year,
	  'yy' => substr($year, 2, 2),
        });

        my @months = sort { $b <=> $a } keys %{$count{$year}};
        if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @months = reverse @months; }
        foreach $month (@months)
        {
	  my $daysinmonth = LJ::days_in_month($month, $year);
	  
	  # TODO: wtf is this doing?  picking a random day that it knows day of week from?  ([0] from hash?)
	  my $firstday = (%{$count{$year}->{$month}})[0];

	  # go backwards from first day
	  my $dayweek = $dayweek{$year}->{$month}->{$firstday};
	  for ($i=$firstday-1; $i>0; $i--)
	  {
	      if (--$dayweek < 1) { $dayweek = 7; }
	      $dayweek{$year}->{$month}->{$i} = $dayweek;
	  }
	  # go forwards from first day
	  $dayweek = $dayweek{$year}->{$month}->{$firstday};
	  for ($i=$firstday+1; $i<=$daysinmonth; $i++)
	  {
	      if (++$dayweek > 7) { $dayweek = 1; }
	      $dayweek{$year}->{$month}->{$i} = $dayweek;
	  }

	  my %calendar_month = ();
	  $calendar_month{'monlong'} = LJ::Lang::month_long($u->{'lang'}, $month);
	  $calendar_month{'monshort'} = LJ::Lang::month_short($u->{'lang'}, $month);
	  $calendar_month{'yyyy'} = $year;
	  $calendar_month{'yy'} = substr($year, 2, 2);
	  $calendar_month{'weeks'} = "";
	  $calendar_month{'urlmonthview'} = "$LJ::SITEROOT/view/?type=month&amp;user=$user&amp;y=$year&amp;m=$month";
	  my $weeks = \$calendar_month{'weeks'};

	  my %calendar_week = ();
	  $calendar_week{'emptydays_beg'} = "";
	  $calendar_week{'emptydays_end'} = "";
	  $calendar_week{'days'} = "";

	  # start the first row and check for its empty spaces
	  my $rowopen = 1;
	  if ($dayweek{$year}->{$month}->{1} != 1)
	  {
	      my $spaces = $dayweek{$year}->{$month}->{1} - 1;
	      $calendar_week{'emptydays_beg'} = 
		  &fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
				  { 'numempty' => $spaces });
	  }

	  # make the days!
	  my $days = \$calendar_week{'days'};

	  for (my $i=1; $i<=$daysinmonth; $i++)
	  {
	      $count{$year}->{$month}->{$i} += 0;
	      if (! $rowopen) { $rowopen = 1; }

	      my %calendar_day = ();
	      $calendar_day{'d'} = $i;
	      $calendar_day{'eventcount'} = $count{$year}->{$month}->{$i};
	      if ($count{$year}->{$month}->{$i})
	      {
		$calendar_day{'dayevent'} = &fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
		    'eventcount' => $count{$year}->{$month}->{$i},
		    'dayurl' => "$journalbase/day/" . sprintf("%04d/%02d/%02d", $year, $month, $i),
		});
	      }
	      else
	      {
		$calendar_day{'daynoevent'} = $vars->{'CALENDAR_DAY_NOEVENT'};
	      }

	      $$days .= &fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);

	      if ($dayweek{$year}->{$month}->{$i} == 7)
	      {
		$$weeks .= &fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
		$rowopen = 0;
		$calendar_week{'emptydays_beg'} = "";
		$calendar_week{'emptydays_end'} = "";
		$calendar_week{'days'} = "";
	      }
	  }

	  # if rows is still open, we have empty spaces
	  if ($rowopen)
	  {
	      if ($dayweek{$year}->{$month}->{$daysinmonth} != 7)
	      {
		$spaces = 7 - $dayweek{$year}->{$month}->{$daysinmonth};
		$calendar_week{'emptydays_end'} = 
		    &fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
				{ 'numempty' => $spaces });
	      }
	      $$weeks .= &fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
	  }

	  $$months .= &fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
        } # end foreach months

    } # end foreach years

    ######## new code

    $$ret .= &fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;  
}

# the creator for the 'day' view:
sub create_view_day
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $user = $u->{'user'};

    LJ::load_user_props($dbs, $u, "opt_blockrobots", "url", "urlname");
    my %day_page = ();
    $day_page{'username'} = $user;
    if ($u->{'opt_blockrobots'}) {
	$day_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    $day_page{'head'} .= 
	$vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};
    $day_page{'name'} = LJ::ehtml($u->{'name'});
    $day_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";

    if ($u->{'url'} =~ m!^http://!) {
	$day_page{'website'} =
	    &fill_var_props($vars, 'DAY_WEBSITE', {
		"url" => LJ::ehtml($u->{'url'}),
		"name" => LJ::ehtml($u->{'urlname'} || "My Website"),
	    });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $day_page{'urlfriends'} = "$journalbase/friends";
    $day_page{'urlcalendar'} = "$journalbase/calendar";
    $day_page{'urllastn'} = "$journalbase/";

    my $initpagedates = 0;
    my $quser = $dbr->quote($user);
    my $qremoteuser = $dbr->quote($remote->{'user'});
    my $qremoteid = $remote->{'userid'}+0;

    my %FORM = ();
    &get_form_data(\%FORM);
    my $month = $FORM{'month'};
    my $day = $FORM{'day'};
    my $year = $FORM{'year'};
    my @errors = ();

    if ($opts->{'args'} =~ m!^/(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
	($month, $day, $year) = ($2, $3, $1);
    }

    if ($year !~ /^\d+$/) { push @errors, "Corrupt or non-existant year."; }
    if ($month !~ /^\d+$/) { push @errors, "Corrupt or non-existant month."; }
    if ($day !~ /^\d+$/) { push @errors, "Corrupt or non-existant day."; }
    if ($month < 1 || $month > 12 || int($month) != $month) { push @errors, "Invalid month."; }
    if ($year < 1970 || $year > 2038 || int($year) != $year) { push @errors, "Invalid year: $year"; }
    if ($day < 1 || $day > 31 || int($day) != $day) { push @errors, "Invalid day."; }
    if (scalar(@errors)==0 && $day > LJ::days_in_month($month, $year)) { push @errors, "That month doesn't have that many days."; }

    if (@errors)
    {
        $$ret .= "Errors occurred processing this page:\n<UL>\n";		
        foreach (@errors)
        {
	  $$ret .= "<LI>$_\n";
        }
        $$ret .= "</UL>\n";
        return 0;
    }

    my %talkcount = ();
    my @itemids = ();
    my $quser = $dbr->quote($user);

    my $optDESC = $vars->{'DAY_SORT_MODE'} eq "reverse" ? "DESC" : "";

    $sth = $dbr->prepare(<<"END_SQL"
SELECT itemid 
FROM log l LEFT JOIN friends f ON l.ownerid=f.userid AND f.friendid=$qremoteid
WHERE l.ownerid=$u->{'userid'}
AND year=$year AND month=$month AND day=$day
AND ((l.security='public')
  OR (l.security='usemask' AND l.allowmask & f.groupmask)
  OR (l.ownerid=$qremoteid))
ORDER BY l.eventtime LIMIT 200
END_SQL
);
   
    $sth->execute;
    if ($dbr->err) {
	$$ret .= $dbr->errstr;
	return 1;
    }

    push @itemids, $_->{'itemid'} while ($_ = $sth->fetchrow_hashref);

    my $itemid_in = join(", ", map { $_+0; } @itemids);

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props($dbs, \@itemids, \%logprops);
    LJ::load_moods($dbs);

    my $logtext = LJ::get_logtext($dbs, @itemids);

    # load the log items
    $sth = $dbr->prepare("SELECT itemid, security, replycount, DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H\") AS 'alldatepart' FROM log l WHERE itemid IN ($itemid_in) ORDER BY eventtime $optDESC, logtime $optDESC");
    $sth->execute;

    my $events = "";
    while (my ($itemid, $security, $replycount, $alldatepart) = $sth->fetchrow_array)
    {
	my $subject = $logtext->{$itemid}->[0];
	my $event = $logtext->{$itemid}->[1];

        my @dateparts = split(/ /, $alldatepart);
        my %day_date_format = (
			 'dayshort' => $dateparts[0],
			 'daylong' => $dateparts[1],
			 'monshort' => $dateparts[2],
			 'monlong' => $dateparts[3],
			 'yy' => $dateparts[4],
			 'yyyy' => $dateparts[5],
			 'm' => $dateparts[6],
			 'mm' => $dateparts[7],
			 'd' => $dateparts[8],
			 'dd' => $dateparts[9],
			 'dth' => $dateparts[10],
			 'ap' => substr(lc($dateparts[11]),0,1),
			 'AP' => substr(uc($dateparts[11]),0,1),
			 'ampm' => lc($dateparts[11]),
			 'AMPM' => $dateparts[11],
			 'min' => $dateparts[12],
			 '12h' => $dateparts[13],
			 '12hh' => $dateparts[14],
			 '24h' => $dateparts[15],
			 '24hh' => $dateparts[16],
			 );

        unless ($initpagedates)
        {
	  foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth))
	  {
	      $day_page{$_} = $day_date_format{$_};
	  }
	  $initpagedates = 1;
        }

        my %day_event = ();
	$day_event{'itemid'} = $itemid;
        $day_event{'datetime'} = &fill_var_props($vars, 'DAY_DATE_FORMAT', \%day_date_format);
	if ($subject) {
	    LJ::CleanHTML::clean_subject(\$subject);
	    $day_event{'subject'} = &fill_var_props($vars, 'DAY_SUBJECT', { 
		"subject" => $subject,
	    });
	}

	LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
					       'cuturl' => LJ::item_link($u, $itemid), });
	LJ::expand_embedded($dbs, $itemid, $remote, \$event);
        $day_event{'event'} = $event;

	if ($u->{'opt_showtalklinks'} eq "Y" &&
	    ! $logprops{$itemid}->{'opt_nocomments'}
	    ) {
	    $day_event{'talklinks'} = &fill_var_props($vars, 'DAY_TALK_LINKS', {
		'itemid' => $itemid,
		'urlpost' => "$LJ::SITEROOT/talkpost.bml?itemid=$itemid",
		'readlink' => $replycount ? &fill_var_props($vars, 'DAY_TALK_READLINK', {
		    'urlread' => "$LJ::SITEROOT/talkread.bml?itemid=$itemid&amp;nc=$replycount",
		    'messagecount' => $replycount,
		    'mc-plural-s' => $replycount==1 ? "" : "s",
		    'mc-plural-es' => $replycount == 1 ? "" : "es",
		    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
		}) : "",
	    });
	}

	## current stuff
	&prepare_currents({ 'props' => \%logprops, 
			    'itemid' => $itemid, 
			    'vars' => $vars, 
			    'prefix' => "DAY",
			    'event' => \%day_event,
			    'user' => $u,
			});

	my $var = 'DAY_EVENT';
	if ($security eq "private" && 
	    $vars->{'DAY_EVENT_PRIVATE'}) { $var = 'DAY_EVENT_PRIVATE'; }
	if ($security eq "usemask" && 
	    $vars->{'DAY_EVENT_PROTECTED'}) { $var = 'DAY_EVENT_PROTECTED'; }
	    
        $events .= &fill_var_props($vars, $var, \%day_event);
    }

    if (! $initpagedates)
    {
        # if no entries were on that day, we haven't populated the time shit!
        $sth = $dbr->prepare("SELECT DATE_FORMAT('$year-$month-$day', '%a %W %b %M %y %Y %c %m %e %d %D') AS 'alldatepart'");
        $sth->execute;
        my @dateparts = split(/ /, $sth->fetchrow_arrayref->[0]);
        foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth))
        {
	  $day_page{$_} = shift @dateparts;
        }

        $day_page{'events'} = &fill_var_props($vars, 'DAY_NOEVENTS', {});
    }
    else
    {
        $day_page{'events'} = &fill_var_props($vars, 'DAY_EVENTS', { 'events' => $events });
        $events = "";  # free some memory maybe
    }

    # calculate previous day
    my $pdyear = $year;
    my $pdmonth = $month;
    my $pdday = $day-1;
    if ($pdday < 1)
    {
        if (--$pdmonth < 1)
        {
	  $pdmonth = 12;
	  $pdyear--;
        }
        $pdday = LJ::days_in_month($pdmonth, $pdyear);
    }

    # calculate next day
    my $nxyear = $year;
    my $nxmonth = $month;
    my $nxday = $day+1;
    if ($nxday > LJ::days_in_month($nxmonth, $nxyear))
    {
        $nxday = 1;
        if (++$nxmonth > 12) { ++$nxyear; $nxmonth=1; }
    }
    
    $day_page{'prevday_url'} = "$journalbase/day/" . sprintf("%04d/%02d/%02d", $pdyear, $pdmonth, $pdday); 
    $day_page{'nextday_url'} = "$journalbase/day/" . sprintf("%04d/%02d/%02d", $nxyear, $nxmonth, $nxday); 

    $$ret .= &fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

1;
