use strict;
package LJ::S2;

sub RecentPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u);
    $p->{'_type'} = "RecentPage";
    $p->{'view'} = "recent";
    $p->{'entries'} = [];

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $dbcr;
    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }
    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'});
        return;
    }

    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    my %FORM = ();
    LJ::decode_url_string($opts->{'args'}, \%FORM);

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }
    
    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }

    if ($FORM{'skip'}) {
        # if followed a skip link back, prevent it from going back further
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex,nofollow\">\n";
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\">\n";
    }

    # "Automatic Discovery of RSS feeds"
    $p->{'head_content'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$p->{'base_url'}/rss" />\n};
    
    my $quser = $dbh->quote($user);
    
    my $itemshow = S2::get_property_value($opts->{'ctx'}, "page_recent_items")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }
    

    my $skip = $FORM{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to view all entries, regardless of security?
    my $viewall = 0;
    if ($FORM{'viewall'} && LJ::check_priv($dbs, $remote, "viewall")) {
        LJ::statushistory_add($dbs, $u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "lastn: $user");
        $viewall = 1;
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items($dbs, {
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'dateformat' => 'S2',
        'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")  # community or syndicated
            ? "logtime" : "",
        'err' => \$err,
    });

    die $err if $err;
    
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

    my $lastdate = "";
    my $itemnum = 0;
    my $lastentry = undef;

    my (%apu, %apu_lite);  # alt poster users; UserLite objects
    foreach (@items) {
        next unless $_->{'posterid'} != $u->{'userid'};
        $apu{$_->{'posterid'}} = undef;
    }
    if (%apu) {
        my $in = join(',', keys %apu);
        my $sth = $dbr->prepare("SELECT userid, user, defaultpicid, statusvis, name, journaltype ".
                                "FROM user WHERE userid IN ($in)");
        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            $apu{$_->{'userid'}} = $_;
            $apu_lite{$_->{'userid'}} = UserLite($_);
        }
    }

    my $userlite_journal = UserLite($u);

    foreach my $item (@items) 
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(posterid itemid security alldatepart replycount);

        my $subject = $logtext->{$itemid}->[0];
        my $text = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($dbs, $u, \$subject, \$text, $logprops{$itemid});
	}

        my $date = substr($alldatepart, 0, 10);
        my $new_day = 0;
        if ($date ne $lastdate) {
            $new_day = 1;
            $lastdate = $date;
            $lastentry->{'end_day'} = 1 if $lastentry;
        }

        $itemnum++;
        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $u->{'clusterid'} ? ($itemid * 256 + $item->{'anum'}) : $itemid;
        my $itemargs = $u->{'clusterid'} ? "journal=$user&itemid=$ditemid" : "itemid=$ditemid";
        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$text);

        my $nc;
        $nc .= "&nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};
        
        my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs$nc";
        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
            'count' => $replycount,
            'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! $logprops{$itemid}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$itemid}->{'hasscreened'} && ($remote->{'user'} eq $u->{'user'}|| LJ::check_priv($dbs, $remote, "sharedjournal", $user))) ? 1 : 0,
        });
        
        my $userlite_poster = $userlite_journal;
        my $userpic = $p->{'journal'}->{'default_pic'};
        if ($u->{'userid'} != $posterid) {
            $userlite_poster = $apu_lite{$posterid} or die "No apu_lite for posterid=$posterid";
            $userpic = Image_userpic($apu{$posterid}, 0, $logprops{$itemid}->{'picture_keyword'});
        }

        my $entry = $lastentry = Entry($u, {
            'subject' => $subject,
            'text' => $text,
            'dateparts' => $alldatepart,
            'security' => $security,
            'props' => $logprops{$itemid},
            'itemid' => $ditemid,
            'journal' => $userlite_journal,
            'poster' => $userlite_poster,
            'comments' => $comments,
            'new_day' => $new_day,
            'end_day' => 0,   # if true, set later
            'userpic' => $userpic,
        });

        push @{$p->{'entries'}}, $entry;

    } # end huge while loop


    #### make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
    };

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        $newskip = 0 if $newskip <= 0;
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_url'} = $newskip ? "$p->{'base_url'}/?skip=$newskip" : "$p->{'base_url'}/";
        $nav->{'forward_count'} = $itemshow;
    }

    # unless we didn't even load as many as we were expecting on this
    # page, then there are more (unless there are exactly the number shown 
    # on the page, but who cares about that)
    unless ($itemnum != $itemshow) {
        $nav->{'backward_count'} = $itemshow;
        if ($skip == $maxskip) {
            my $date_slashes = $lastdate;  # "yyyy mm dd";
            $date_slashes =~ s! !/!g;
            $nav->{'backward_url'} = "$p->{'base_url'}/day/$date_slashes";
        } else {
            my $newskip = $skip + $itemshow;
            $nav->{'backward_url'} = "$p->{'base_url'}/?skip=$newskip";
            $nav->{'backward_skip'} = $newskip;
        }
    }

    $p->{'nav'} = $nav;
    return $p;
}

1;
