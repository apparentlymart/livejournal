use strict;
package LJ::S2;

sub RecentPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "RecentPage";
    $p->{'view'} = "recent";
    $p->{'entries'} = [];

    my $user = $u->{'user'};
    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    my $datalink = sub {
        my ($what, $caption) = @_;
        return Link($p->{'base_url'} . "/data/$what",
                    $caption,
                    Image("$LJ::IMGPREFIX/data_$what.gif", 32, 15, $caption));
    };

    $p->{'data_link'} = {
        'rss' => $datalink->('rss', 'RSS'),
        'atom' => $datalink->('atom', 'Atom'),
    };
    $p->{'data_links_order'} = [ qw(rss atom) ];

    LJ::load_user_props($remote, "opt_nctalklinks", "opt_ljcut_disable_lastn");

    my $get = $opts->{'getargs'};

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    if ($u->{'opt_blockrobots'} || $get->{'skip'}) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    $p->{'head_content'} .= qq{<link rel="openid.server" href="$LJ::OPENID_SERVER" />\n}
        if LJ::OpenID::server_enabled();

    $p->{'head_content'} .= qq{<meta http-equiv="X-YADIS-Location" content="$journalbase/data/yadis" />\n};

    if (my $icbm = $u->prop("icbm")) {
        $p->{'head_content'} .= qq{<meta name="ICBM" content="$icbm" />\n};
    }

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "page_recent_items")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = $LJ::MAX_SCROLLBACK_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to view all entries, regardless of security?
    my $viewall = 0;
    my $viewsome = 0;
    if ($get->{'viewall'} && LJ::check_priv($remote, "canview")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                              "viewall", "lastn: $user, statusvis: $u->{'statusvis'}");
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'tagids' => $opts->{tagids},
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
    LJ::load_log_props2($u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);

    my $lastdate = "";
    my $itemnum = 0;
    my $lastentry = undef;

    my (%apu, %apu_lite);  # alt poster users; UserLite objects
    foreach (@items) {
        next unless $_->{'posterid'} != $u->{'userid'};
        $apu{$_->{'posterid'}} = undef;
    }
    if (%apu) {
        LJ::load_userids_multiple([map { $_, \$apu{$_} } keys %apu], [$u]);
        $apu_lite{$_} = UserLite($apu{$_}) foreach keys %apu;
    }

    # load tags
    my $idsbyc = { $u->{clusterid} => [ ] };
    push @{$idsbyc->{$u->{clusterid}}}, [ $u->{userid}, $_->{itemid} ]
        foreach @items;
    my $tags = LJ::Tags::get_logtagsmulti($idsbyc);

    my $userlite_journal = UserLite($u);

  ENTRY:
    foreach my $item (@items)
    {
        my ($posterid, $itemid, $security, $alldatepart) =
            map { $item->{$_} } qw(posterid itemid security alldatepart);

        my $replycount = $logprops{$itemid}->{'replycount'};
        my $subject = $logtext->{$itemid}->[0];
        my $text = $logtext->{$itemid}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $text    =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        # don't show posts from suspended users unless the user doing the viewing says to (and is allowed)
        next ENTRY if $apu{$posterid} && $apu{$posterid}->{'statusvis'} eq 'S' && !$viewsome;

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$subject, \$text, $logprops{$itemid});
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

        my $ditemid = $itemid * 256 + $item->{'anum'};
        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}),
                                              'ljcut_disable' => $remote->{"opt_ljcut_disable_lastn"}, });
        LJ::expand_embedded($u, $ditemid, $remote, \$text);

        my @taglist;
        while (my ($kwid, $kw) = each %{$tags->{"$u->{userid} $itemid"} || {}}) {
            push @taglist, Tag($u, $kwid => $kw);
        }
        @taglist = sort { $a->{name} cmp $b->{name} } @taglist;

        if ($opts->{enable_tags_compatibility} && @taglist) {
            $text .= LJ::S2::get_tags_text($opts->{ctx}, \@taglist);
        }

        my $nc = "";
        $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

        my $permalink = "$journalbase/$ditemid.html";
        my $readurl = $permalink;
        $readurl .= "?$nc" if $nc;
        my $posturl = $permalink . "?mode=reply";

        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => $posturl,
            'count' => $replycount,
            'maxcomments' => ($replycount >= LJ::get_cap($u, 'maxcomments')) ? 1 : 0,
            'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! $logprops{$itemid}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$itemid}->{'hasscreened'} && ($remote->{'user'} eq $u->{'user'}|| LJ::can_manage($remote, $u))) ? 1 : 0,
        });

        my $userlite_poster = $userlite_journal;
        my $pu = $u;
        if ($u->{'userid'} != $posterid) {
            $userlite_poster = $apu_lite{$posterid} or die "No apu_lite for posterid=$posterid";
            $pu = $apu{$posterid};
        }
        my $userpic = Image_userpic($pu, 0, $logprops{$itemid}->{'picture_keyword'});

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
            'tags' => \@taglist,
            'userpic' => $userpic,
            'permalink_url' => $permalink,
        });

        push @{$p->{'entries'}}, $entry;

    } # end huge while loop

    # mark last entry as closing.
    $p->{'entries'}->[-1]->{'end_day'} = 1 if $itemnum;

    #### make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
        'count' => $itemnum,
    };

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        $newskip = 0 if $newskip <= 0;
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_url'} = LJ::make_link("$p->{base_url}/", { skip => ($newskip || ""), tag => (LJ::eurl($get->{tag}) || "") });
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
            $nav->{'backward_url'} = LJ::make_link("$p->{'base_url'}/", { skip => ($newskip || ""), tag => (LJ::eurl($get->{tag}) || "") });
            $nav->{'backward_skip'} = $newskip;
        }
    }

    $p->{'nav'} = $nav;
    return $p;
}

1;
