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
    my $dbcr;

    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }

    my $user = $u->{'user'};

    LJ::load_user_props($dbs, $u, "opt_blockrobots", "url", "urlname");
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }
    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    my %FORM = ();
    LJ::get_form_data(\%FORM);

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
            LJ::fill_var_props($vars, 'LASTN_USERPIC', {
                "src" => "$LJ::SITEROOT/userpic/$picid",
                "width" => $userpics{$picid}->{'width'},
                "height" => $userpics{$picid}->{'height'},
            });
    }

    if ($u->{'url'} =~ m!^https?://!) {
        $lastn_page{'website'} =
            LJ::fill_var_props($vars, 'LASTN_WEBSITE', {
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
    if ($LJ::UNICODE) {
        $lastn_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'">';
    }
    $lastn_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    $events = \$lastn_page{'events'};
    
    my $quser = $dbh->quote($user);
    
    my $itemshow = $vars->{'LASTN_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $FORM{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to 
    my $viewall = 0;
    if ($FORM{'viewall'} && LJ::check_priv($dbs, $remote, "viewall")) {
        LJ::statushistory_add($dbs, $u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "lastn: $user");
        $viewall = 1;
    }

    ## load the itemids
    my @itemids;
    my @items = LJ::get_recent_items($dbs, {
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'order' => $u->{'journaltype'} eq "C" ? "logtime" : "",
    });
    
    ### load the log properties
    my %logprops = ();
    my $logtext;
    if ($u->{'clusterid'}) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($dbcr, $u->{'userid'}, \@itemids, \%logprops);
        $logtext = LJ::get_logtext2($u, @itemids);
    } else {
        LJ::load_log_props($dbs, \@itemids, \%logprops);
        $logtext = LJ::get_logtext($dbs, @itemids);
    }
    LJ::load_moods($dbs);

    my $lastday = -1;
    my $lastmonth = -1;
    my $lastyear = -1;
    my $eventnum = 0;

    my %altposter_picid = ();  # map ALT_POSTER userids to defaultpicids

    foreach my $item (@items) 
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(posterid itemid security alldatepart replycount);

        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($dbs, $u, \$subject, \$event, $logprops{$itemid});
	}

        my %lastn_date_format = LJ::alldateparts_to_hash($alldatepart);

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
              $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});
          }
          $$events .= LJ::fill_var_props($vars, 'LASTN_NEW_DAY', \%lastn_new_day);

          $lastday = $lastn_date_format{'d'};
          $lastmonth = $lastn_date_format{'m'};
          $lastyear = $lastn_date_format{'yyyy'};
        }

        my %lastn_event = ();
        $eventnum++;
        $lastn_event{'eventnum'} = $eventnum;
        $lastn_event{'itemid'} = $itemid;
        $lastn_event{'datetime'} = LJ::fill_var_props($vars, 'LASTN_DATE_FORMAT', \%lastn_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $lastn_event{'subject'} = LJ::fill_var_props($vars, 'LASTN_SUBJECT', { 
                "subject" => $subject,
            });
        }

        my $ditemid = $u->{'clusterid'} ? ($itemid * 256 + $item->{'anum'}) : $itemid;
        my $itemargs = $u->{'clusterid'} ? "journal=$user&itemid=$ditemid" : "itemid=$ditemid";
        $lastn_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$event);
        $lastn_event{'event'} = $event;

        if ($u->{'opt_showtalklinks'} eq "Y" && 
            ! $logprops{$itemid}->{'opt_nocomments'}
            ) 
        {
            $itemargs .= "&nc=$replycount" if $replycount && $remote->{'opt_nctalklinks'};
            my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs";
            $lastn_event{'talklinks'} = LJ::fill_var_props($vars, 'LASTN_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $replycount ? LJ::fill_var_props($vars, 'LASTN_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents($dbs, {
            'props' => \%logprops, 
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
                $lastn_altposter{'pic'} = LJ::fill_var_props($vars, 'LASTN_ALTPOSTER_PIC', {
                    "src" => "$LJ::SITEROOT/userpic/$picid",
                    "width" => $pic->{$picid}->{'width'},
                    "height" => $pic->{$picid}->{'height'},
                });
            }
            $lastn_event{'altposter'} = 
                LJ::fill_var_props($vars, 'LASTN_ALTPOSTER', \%lastn_altposter);
        }

        my $var = 'LASTN_EVENT';
        if ($security eq "private" && 
            $vars->{'LASTN_EVENT_PRIVATE'}) { $var = 'LASTN_EVENT_PRIVATE'; }
        if ($security eq "usemask" && 
            $vars->{'LASTN_EVENT_PROTECTED'}) { $var = 'LASTN_EVENT_PROTECTED'; }
        $$events .= LJ::fill_var_props($vars, $var, \%lastn_event);
    } # end huge while loop

    $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});

    if ($skip) {
        $lastn_page{'range'} = 
            LJ::fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
                "numitems" => $eventnum,
                "skip" => $skip,
            });
    } else {
        $lastn_page{'range'} = 
            LJ::fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
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
            LJ::fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
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
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                    "numitems" => "Day",
                    "url" => "$journalbase/day/" . sprintf("%04d/%02d/%02d", $lastyear, $lastmonth, $lastday),
                });
        } else {
            my $newskip = $skip + $itemshow;
            $newskip = "?skip=$newskip";
            $skiplinks{'skipbackward'} = 
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
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
            LJ::fill_var_props($vars, 'LASTN_SKIP_LINKS', \%skiplinks);
    }

    $$ret = LJ::fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $user = $u->{'user'};
    my $env = $opts->{'env'};

    # fill in all remote details if present (caps, especially)
    $remote = LJ::load_userid($dbs, $remote->{'userid'}) if $remote;

    # see how often the remote user can reload this page.  there're
    # two methos to this. "friendsviewupdate" which just sends a "not
    # modified" header after a quick check here, and the "fvbo" cookie
    # (friends view back off) which is meant to have a longer delay,
    # and gets handled by apache and mod_rewrite instead of this
    # codepath.  first check is for the cookie.  
    my $nowtime = time();
    my $backofftime = LJ::get_cap_min($remote, "cookiebackoff");

    # If there is a non-zero value returned, we're setting the back off:
    if ($backofftime)  {
        # Note: You can't set a short-expiration cookie reliably with
        # IE since it doesn't use the server's Date:, only the
        # client's, which is so often inaccurate.  so we're not going
        # to use this code, but it'll stay here if people want to try.
        my @cookies = LJ::make_cookie("fvbo", $user, ($nowtime+$backofftime), $LJ::COOKIE_PATH);
        $opts->{'headers'}->{'Set-Cookie'} = \@cookies;
    }

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::get_cap_min($remote, "friendsviewupdate") || 1;

    # when are we going to say page was last modified?  back up to the 
    # most recent time in the past where $time % $interval == 0
    my $lastmod = $nowtime;
    $lastmod -= $lastmod % $newinterval;

    # see if they have a previously cached copy of this page they
    # might be able to still use.
    if ($env->{'HTTP_IF_MODIFIED_SINCE'}) {
        my $theirtime = LJ::http_to_time($env->{'HTTP_IF_MODIFIED_SINCE'});

        # send back a 304 Not Modified if they say they've reloaded this 
        # document in the last $newinterval seconds:
        unless ($theirtime < $lastmod) {
            $opts->{'status'} = "304 Not Modified";
            $opts->{'nocontent'} = 1;
            return 1;
        }
    }
    $opts->{'headers'}->{'Last-Modified'} = LJ::time_to_http($lastmod);

    $$ret = "";

    my %FORM = ();
    LJ::get_form_data(\%FORM);

    if ($FORM{'mode'} eq "live") {
        $$ret .= "<html><head><title>${user}'s friends: live!</title></head>\n";
        $$ret .= "<frameset rows=\"100%,0%\" border=0>\n";
        $$ret .= "  <frame name=livetop src=\"friends?mode=framed\">\n";
        $$ret .= "  <frame name=livebottom src=\"friends?mode=livecond&amp;lastitemid=0\">\n";
        $$ret .= "</frameset></html>\n";
        return 1;
    }

    LJ::load_user_props($dbs, $u, "opt_usesharedpic", "url", "urlname");
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }
    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    my %friends_page = ();
    $friends_page{'name'} = LJ::ehtml($u->{'name'});
    $friends_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $user;
    $friends_page{'numitems'} = $vars->{'FRIENDS_OPT_ITEMS'} || 20;

    ## never have spiders index friends pages (change too much, and some 
    ## people might not want to be indexed)
    $friends_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    if ($LJ::UNICODE) {
        $friends_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'">';
    }
    $friends_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'FRIENDS_HEAD'};

    if ($u->{'url'} =~ m!^https?://!) {
        $friends_page{'website'} =
            LJ::fill_var_props($vars, 'FRIENDS_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    $friends_page{'urlcalendar'} = "$journalbase/calendar";
    $friends_page{'urllastn'} = "$journalbase/";

    $friends_page{'events'} = "";

    my $quser = $dbr->quote($user);

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
            if ($group) { $group = LJ::durl($group); }
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
        my @items = LJ::get_friend_items($dbs, {
            'userid' => $u->{'userid'},
            'remote' => $remote,
            'itemshow' => 1,
            'skip' => 0,
            'filter' => $filter,
        });
        my $first = @items ? $items[0]->{'itemid'} : 0;

        $$ret .= "time = " . scalar(time()) . "<br>";
        $opts->{'headers'}->{'Refresh'} = "30;URL=$LJ::SITEROOT/users/$user/friends?mode=livecond&lastitemid=$first";
        if ($FORM{'lastitemid'} == $first) {
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
    my @itemids;  #DIE
    my %idsbycluster;
    my @items = LJ::get_friend_items($dbs, {
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'filter' => $filter,
        'owners' => \%owners,
        'itemids' => \@itemids,  #DIE
        'idsbycluster' => \%idsbycluster,
    });

    my $ownersin = join(",", keys %owners);

    my %friends = ();
    $sth = $dbr->prepare("SELECT u.user, u.userid, u.clusterid, f.fgcolor, f.bgcolor, u.name, u.defaultpicid, u.opt_showtalklinks, u.moodthemeid, u.statusvis, u.oldenc FROM friends f, user u WHERE u.userid=f.friendid AND f.userid=$u->{'userid'} AND f.friendid IN ($ownersin)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        next unless ($_->{'statusvis'} eq "V");  # ignore suspended/deleted users.
        $_->{'fgcolor'} = LJ::color_fromdb($_->{'fgcolor'});
        $_->{'bgcolor'} = LJ::color_fromdb($_->{'bgcolor'});
        $friends{$_->{'userid'}} = $_;
    }

    unless (%friends)
    {
        $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
          "name" => LJ::ehtml($u->{'name'}),
          "name-\'s" => ($u->{'name'} =~ /s$/i) ? "'" : "'s",
          "username" => $user,
        });

        $$ret .= "<base target='_top'>" if ($FORM{'mode'} eq "framed");
        $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
        return 1;
    }

    $friendsin = join(", ", map { $dbr->quote($_) } keys %friends);
    
    ### load the log properties
    my %logprops = ();  # key is "$owneridOrZero $[j]itemid"
    LJ::load_props($dbs, "log");
    LJ::load_log_props2multi($dbs, \%idsbycluster, \%logprops);
    LJ::load_moods($dbs);

    # load the pictures for the user
    my %userpics;
    my @picids = map { $friends{$_}->{'defaultpicid'} } keys %friends;
    LJ::load_userpics($dbs, \%userpics, [ @picids ]);

    # load the text of the entries
    my $logtext = LJ::get_logtext2multi($dbs, \%idsbycluster);
  
    my %posterdefpic;  # map altposter userids -> default picture ids
    
    my %friends_events = ();
    my $events = \$friends_events{'events'};
    
    my $lastday = -1;
    my $eventnum = 0;
    foreach my $item (@items) 
    {
        my ($friendid, $posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(ownerid posterid itemid security alldatepart replycount);

        my $clusterid = $item->{'clusterid'}+0;
        
        my $datakey = "0 $itemid";   # no cluster
        $datakey = "$friendid $itemid" if $clusterid;
            
        my $subject = $logtext->{$datakey}->[0];
        my $event = $logtext->{$datakey}->[1];

        if ($LJ::UNICODE && $logprops{$datakey}->{'unknown8bit'}) {
            LJ::item_toutf8($dbs, $friends{$friendid}, \$subject, \$event, $logprops{$datakey});
        }

        my ($friend, $poster);
        $friend = $friends{$friendid}->{'user'};
        $poster = LJ::get_username($dbs, $posterid);
        
        $eventnum++;
        my %friends_date_format = LJ::alldateparts_to_hash($alldatepart);

        if ($lastday != $friends_date_format{'d'})
        {
            my %friends_new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
            {
                $friends_new_day{$_} = $friends_date_format{$_};
            }
            unless ($lastday==-1) {
                $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
            }
            $$events .= LJ::fill_var_props($vars, 'FRIENDS_NEW_DAY', \%friends_new_day);
            $lastday = $friends_date_format{'d'};
        }
        
        my %friends_event = ();
        $friends_event{'itemid'} = $itemid;
        $friends_event{'datetime'} = LJ::fill_var_props($vars, 'FRIENDS_DATE_FORMAT', \%friends_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_SUBJECT', { 
                "subject" => $subject,
            });
        } else {
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_NO_SUBJECT', { 
                "friend" => $friend,
                "name" => $friends{$friendid}->{'name'},
            });
        }
        
        my $ditemid = $clusterid ? ($itemid * 256 + $item->{'anum'}) : $itemid;
        my $itemargs = $clusterid ? "journal=$friend&itemid=$ditemid" : "itemid=$ditemid";
        $friends_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$datakey}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($friends{$friendid}, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$event);
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
            if ($logprops{$datakey}->{'picture_keyword'} && 
                (! $u->{'opt_usesharedpic'} || ($posterid == $friendid))) 
            {
                my $qkw = $dbr->quote($logprops{$datakey}->{'picture_keyword'});
                my $sth = $dbr->prepare("SELECT m.picid FROM userpicmap m, keywords k ".
                                        "WHERE m.userid=$posterid AND m.kwid=k.kwid AND k.keyword=$qkw");
                $sth->execute;
                my ($alt_picid) = $sth->fetchrow_array;
                if ($alt_picid) {
                    LJ::load_userpics($dbs, \%userpics, [ $alt_picid ]);
                    $picid = $alt_picid;
                }
            }
            if ($picid) {
                $friends_event{'friendpic'} = 
                    LJ::fill_var_props($vars, 'FRIENDS_FRIENDPIC', {
                        "src" => "$LJ::SITEROOT/userpic/$picid",
                        "width" => $userpics{$picid}->{'width'},
                        "height" => $userpics{$picid}->{'height'},
                    });
            }
        }
        
        if ($friend ne $poster) {
            $friends_event{'altposter'} = 
                LJ::fill_var_props($vars, 'FRIENDS_ALTPOSTER', {
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
            ! $logprops{$datakey}->{'opt_nocomments'}
            ) 
        {
            $itemargs .= "&nc=$replycount" if $replycount && $remote->{'opt_nctalklinks'};
            my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs";
            $friends_event{'talklinks'} = LJ::fill_var_props($vars, 'FRIENDS_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $replycount ? LJ::fill_var_props($vars, 'FRIENDS_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents($dbs, {
            'props' => \%logprops, 
            'datakey' => $datakey, 
            'vars' => $vars, 
            'prefix' => "FRIENDS",
            'event' => \%friends_event,
            'user' => ($u->{'opt_forcemoodtheme'} eq "Y" ? $u :
                       $friends{$friendid}),
        });

        my $var = 'FRIENDS_EVENT';
        if ($security eq "private" && 
            $vars->{'FRIENDS_EVENT_PRIVATE'}) { $var = 'FRIENDS_EVENT_PRIVATE'; }
        if ($security eq "usemask" && 
            $vars->{'FRIENDS_EVENT_PROTECTED'}) { $var = 'FRIENDS_EVENT_PROTECTED'; }
        
        $$events .= LJ::fill_var_props($vars, $var, \%friends_event);
    } # end while

    $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    ### set the range property (what entries are we looking at)

    if ($skip) {
        $friends_page{'range'} = 
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
                "numitems" => $eventnum,
                "skip" => $skip,
            });
    } else {
        $friends_page{'range'} = 
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
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
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link("$journalbase/friends", \%linkvars),
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
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link("$journalbase/friends", \%linkvars),
            });
    }

    ### if they're both on, show a spacer
    if ($skip_f && $skip_b) {
        $skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $friends_page{'skiplinks'} = 
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }
    
    $$ret .= "<BASE TARGET=_top>" if ($FORM{'mode'} eq "framed");
    $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

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
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    my %FORM = ();
    LJ::get_form_data(\%FORM);

    my %calendar_page = ();
    $calendar_page{'name'} = LJ::ehtml($u->{'name'});
    $calendar_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    if ($u->{'opt_blockrobots'}) {
        $calendar_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $calendar_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'">';
    }
    $calendar_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};
    
    $calendar_page{'months'} = "";

    if ($u->{'url'} =~ m!^https?://!) {
        $calendar_page{'website'} =
            LJ::fill_var_props($vars, 'CALENDAR_WEBSITE', {
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

    my ($db, $sql);
    
    if ($u->{'clusterid'}) {
        $db = LJ::get_cluster_reader($u);
        $sql = "SELECT year, month, day, DAYOFWEEK(CONCAT(year, \"-\", month, \"-\", day)) AS 'dayweek', COUNT(*) AS 'count' FROM log2 WHERE journalid=$quserid GROUP BY year, month, day, dayweek";
    } else {
        $db = $dbr;
        $sql = "SELECT year, month, day, DAYOFWEEK(CONCAT(year, \"-\", month, \"-\", day)) AS 'dayweek', COUNT(*) AS 'count' FROM log WHERE ownerid=$quserid GROUP BY year, month, day, dayweek";
    }

    my $sth = $db->prepare($sql);
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
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} = 
            LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    foreach $year (@years)
    {
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
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
          $calendar_month{'urlmonthview'} = "$LJ::SITEROOT/view/?type=month&user=$user&y=$year&m=$month";
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
                  LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
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
                $calendar_day{'dayevent'} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    'eventcount' => $count{$year}->{$month}->{$i},
                    'dayurl' => "$journalbase/day/" . sprintf("%04d/%02d/%02d", $year, $month, $i),
                });
              }
              else
              {
                $calendar_day{'daynoevent'} = $vars->{'CALENDAR_DAY_NOEVENT'};
              }

              $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);

              if ($dayweek{$year}->{$month}->{$i} == 7)
              {
                $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
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
                    LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', 
                                { 'numempty' => $spaces });
              }
              $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
          }

          $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
        } # end foreach months

    } # end foreach years

    ######## new code

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

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
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }
    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    my %day_page = ();
    $day_page{'username'} = $user;
    if ($u->{'opt_blockrobots'}) {
        $day_page{'head'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $day_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'">';
    }
    $day_page{'head'} .= 
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};
    $day_page{'name'} = LJ::ehtml($u->{'name'});
    $day_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";

    if ($u->{'url'} =~ m!^https?://!) {
        $day_page{'website'} =
            LJ::fill_var_props($vars, 'DAY_WEBSITE', {
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

    LJ::load_remote($dbs, $remote);
    my $qremoteid = 0;
    $qremoteid = ($remote->{'userid'}+0) 
        if ($remote && $remote->{'journaltype'} eq "P");

    my %FORM = ();
    LJ::get_form_data(\%FORM);
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

    if (@errors) {
        $$ret .= "Errors occurred processing this page:\n<ul>\n";		
        foreach (@errors) {
          $$ret .= "<li>$_</li>\n";
        }
        $$ret .= "</ul>\n";
        return 0;
    }

    my %talkcount = ();
    my @itemids = ();
    my $quser = $dbr->quote($user);

    my $optDESC = $vars->{'DAY_SORT_MODE'} eq "reverse" ? "DESC" : "";

    my $secwhere = "AND security='public'";
    if ($remote) {
        if ($remote->{'userid'} == $u->{'userid'}) {
            $secwhere = "";   # see everything
        } else {
            my $gmask = $dbr->selectrow_array("SELECT groupmask FROM friends WHERE userid=$u->{'userid'} AND friendid=$remote->{'userid'}");
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    my $logdb;
    if ($u->{'clusterid'}) { 
        $logdb = LJ::get_cluster_reader($u);
        $sth = $logdb->prepare("SELECT jitemid FROM log2 WHERE journalid=$u->{'userid'} ".
                               "AND year=$year AND month=$month AND day=$day $secwhere ".
                               "ORDER BY eventtime LIMIT 200");
    } else {
        $logdb = $dbr;
        $sth = $logdb->prepare("SELECT itemid FROM log WHERE ownerid=$u->{'userid'} ".
                               "AND year=$year AND month=$month AND day=$day $secwhere ".
                               "ORDER BY eventtime LIMIT 200");
    }
    $sth->execute;
    if ($logdb->err) {
        $$ret .= $logdb->errstr;
        return 1;
    }

    push @itemids, $_ while ($_ = $sth->fetchrow_array);

    my $itemid_in = join(", ", map { $_+0; } @itemids);

    ### load the log properties
    my %logprops = ();
    my $logtext;
    if ($u->{'clusterid'}) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
        $logtext = LJ::get_logtext2($u, @itemids);
    } else {
        LJ::load_log_props($dbs, \@itemids, \%logprops);
        $logtext = LJ::get_logtext($dbs, @itemids);
    }
    LJ::load_moods($dbs);

    # load the log items
    if ($u->{'clusterid'}) {
        $sth = $logdb->prepare("SELECT jitemid, security, replycount, DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H\") AS 'alldatepart', anum FROM log2 WHERE journalid=$u->{'userid'} AND jitemid IN ($itemid_in) ORDER BY eventtime $optDESC, logtime $optDESC");
    } else {
        $sth = $dbr->prepare("SELECT itemid, security, replycount, DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H\") AS 'alldatepart' FROM log WHERE itemid IN ($itemid_in) ORDER BY eventtime $optDESC, logtime $optDESC");
    }
    $sth->execute;

    my $events = "";
    while (my ($itemid, $security, $replycount, $alldatepart, $anum) = $sth->fetchrow_array)
    {
        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($dbs, $u, \$subject, \$event, $logprops{$itemid});
	}

        my %day_date_format = LJ::alldateparts_to_hash($alldatepart);

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
        $day_event{'datetime'} = LJ::fill_var_props($vars, 'DAY_DATE_FORMAT', \%day_date_format);
        if ($subject) {
            LJ::CleanHTML::clean_subject(\$subject);
            $day_event{'subject'} = LJ::fill_var_props($vars, 'DAY_SUBJECT', { 
                "subject" => $subject,
            });
        }

        my $ditemid = $u->{'clusterid'} ? ($itemid*256 + $anum) : $itemid;
        my $itemargs = $u->{'clusterid'} ? "journal=$user&itemid=$ditemid" : "itemid=$ditemid";
        $day_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $anum), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$event);
        $day_event{'event'} = $event;

        if ($u->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$itemid}->{'opt_nocomments'}
            ) 
        {
            $itemargs .= "&nc=$replycount" if $replycount && $remote->{'opt_nctalklinks'};
            my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs";
            $day_event{'talklinks'} = LJ::fill_var_props($vars, 'DAY_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $replycount ? LJ::fill_var_props($vars, 'DAY_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents($dbs, {
            'props' => \%logprops, 
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
            
        $events .= LJ::fill_var_props($vars, $var, \%day_event);
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

        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_NOEVENTS', {});
    }
    else
    {
        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_EVENTS', { 'events' => $events });
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

    $$ret .= LJ::fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

# the creator for the RSS XML syndication view
sub create_view_rss
{
    my ($dbs, $ret, $u, $vars, $remote, $opts) = @_;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    
    my $user = $u->{'user'};
    LJ::load_user_props($dbs, $u, "opt_blockrobots", "url", "urlname");
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    ## load the itemids
    my @itemids;
    my @items = LJ::get_recent_items($dbs, {
        'userid' => $u->{'userid'},
        'itemshow' => 50,
        'order' => $u->{'journaltype'} eq "C" ? "logtime" : "",
        'itemids' => \@itemids,
    });

    $opts->{'contenttype'} = 'text/xml; charset='.$opts->{'saycharset'};

    my $logtext = LJ::get_logtext($dbs, @itemids);

    my $clink = "$LJ::SITEROOT/users/$user/";
    my $ctitle = LJ::exml($u->{'name'});
    if ($u->{'journaltype'} eq "C") {
        $clink = "$LJ::SITEROOT/community/$user/";
    }

    $$ret .= "<?xml version='1.0' encoding='$opts->{'saycharset'}' ?>\n";
    $$ret .= "<!DOCTYPE rss PUBLIC \"-//Netscape Communications//DTD RSS 0.91//EN\"\n";
    $$ret .= "             \"http://my.netscape.com/publish/formats/rss-0.91.dtd\">\n";
    $$ret .= "<rss version='0.91'>\n";
    $$ret .= "<channel>\n";
    $$ret .= "  <title>$ctitle</title>\n";
    $$ret .= "  <link>$clink</link>\n";
    $$ret .= "  <description>$ctitle - $LJ::SITENAME</description>\n";
    $$ret .= "  <language>" . lc($u->{'lang'}) . "</language>\n";

    foreach my $it (@items) 
    {
        $$ret .= "<item>\n";

        my $itemid = $it->{'itemid'};

        my $subject = $logtext->{$itemid}->[0] || 
            substr($logtext->{$itemid}->[1], 0, 40);

        # remove HTML crap and encode it:
        LJ::CleanHTML::clean_subject_all(\$subject);
        $subject ||= "(No subject or text)";
        $subject = LJ::exml($subject);

        $$ret .= "<title>$subject</title>\n";
        $$ret .= "<link>$LJ::SITEROOT/talkread.bml?itemid=$itemid</link>\n";

        $$ret .= "</item>\n";
    } # end huge while loop

    $$ret .= "</channel>\n";
    $$ret .= "</rss>\n";

    return 1;
}

1;
