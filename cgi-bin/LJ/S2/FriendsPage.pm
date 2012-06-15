#!/usr/bin/perl
#

use strict;
package LJ::S2;
use Class::Autouse qw/LJ::ContentFlag/;
use LJ::Request;
use LJ::TimeUtil;
use LJ::UserApps;
use LJ::Entry::Repost;

sub FriendsPage
{
    my ($u, $remote, $opts) = @_;

    # Check if we should redirect due to a bad password
    $opts->{'redir'} = LJ::bad_password_redirect({ 'returl' => 1 });
    return 1 if $opts->{'redir'};

    my $p = Page($u, $opts);
    $p->{'_type'} = "FriendsPage";
    $p->{'view'} = "friends";
    $p->{'entries'} = [];
    $p->{'friends'} = {};
    $p->{'friends_title'} = LJ::ehtml($u->{'friendspagetitle'});
    $p->{'filter_active'} = 0;
    $p->{'filter_name'} = "";
    $p->{'head_content'}->set_object_type( $p->{'_type'} );

    my $sth;
    my $user = $u->{'user'};

    # see how often the remote user can reload this page.
    # "friendsviewupdate" time determines what granularity time
    # increments by for checking for new updates
    my $nowtime = time();

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::get_cap_min($remote, "friendsviewupdate") || 1;

    # when are we going to say page was last modified?  back up to the
    # most recent time in the past where $time % $interval == 0
    my $lastmod = $nowtime;
    $lastmod -= $lastmod % $newinterval;

    # see if they have a previously cached copy of this page they
    # might be able to still use.
    if ($opts->{'header'}->{'If-Modified-Since'}) {
        my $theirtime = LJ::TimeUtil->http_to_time($opts->{'header'}->{'If-Modified-Since'});

        # send back a 304 Not Modified if they say they've reloaded this
        # document in the last $newinterval seconds:
        my $uniq = LJ::Request->notes('uniq');
        if ($theirtime > $lastmod && !($uniq && LJ::MemCache::get("loginout:$uniq"))) {
            $opts->{'handler_return'} = 304;
            return 1;
        }
    }
    $opts->{'headers'}->{'Last-Modified'} = LJ::TimeUtil->time_to_http($lastmod);

    my $get = $opts->{'getargs'};

    my $ret;

    LJ::load_user_props($remote, "opt_nctalklinks", "opt_stylemine", "opt_imagelinks", "opt_ljcut_disable_friends");
    if ($remote) {
        LJ::need_string(qw/repost.confirm.delete
                        entry.reference.label.reposted
                        entry.reference.label.title
                        confirm.bubble.yes
                        confirm.bubble.no/);
    }

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "page_friends_items")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;

    my $base = "$u->{'_journalbase'}/$opts->{'view'}";

    my $filter;
    my $group_name    = '';
    my $common_filter = 1;

    my $events_date = 0;
    my $pathextra = $opts->{pathextra};
    if ($pathextra && $pathextra =~ m/^\/(\d\d\d\d)\/(\d\d)\/(\d\d)\/?$/) {
        $base .= $pathextra;
        $events_date = LJ::TimeUtil->mysqldate_to_time("$1-$2-$3");
        $pathextra = '';
        $get->{date} = '';
    }
    elsif ($get->{date} =~ m!^(\d{4})-(\d\d)-(\d\d)$!) {
        $events_date = LJ::TimeUtil->mysqldate_to_time("$1-$2-$3");
    }

    if (defined $get->{'filter'} && $remote && $remote->{'user'} eq $user) {
        $filter = $get->{'filter'};
        $common_filter = 0;
        $p->{'filter_active'} = 1;
        $p->{'filter_name'} = "";
    }
    else {

        # Show group or day log
        if ($pathextra) {
            $group_name = $pathextra;
            $group_name =~ s!^/!!;
            $group_name =~ s!/$!!;

            if ($group_name) {
                $group_name    = LJ::durl($group_name); 
                $common_filter = 0; 

                $p->{'filter_active'} = 1;
                $p->{'filter_name'}   = LJ::ehtml($group_name);

                $base .= "/" . LJ::eurl($group_name);
            }
        }

        my $grp = LJ::get_friend_group($u, { 'name' => $group_name || "Default View" });
        my $bit = $grp->{'groupnum'};
        my $public = $grp->{'is_public'};

        if ($bit && ($public || ($remote && $remote->{'user'} eq $user))) {
            $filter = (1 << $bit);
        }
        elsif ($group_name) {
            if ($remote) {
                $opts->{'badfriendgroup'} = 1;
                return 1;
            }
            else {
                my $redir = LJ::eurl( LJ::Request->current_page_url );
                $opts->{'redir'} = "$LJ::SITEROOT/?returnto=$redir&errmsg=notloggedin";
                return;
            }
        }
    }

    if ($opts->{'view'} eq "friendsfriends") {
        $p->{'friends_mode'} = "friendsfriends";
    }

    ## load the itemids
    my %friends;
    my %friends_row;
    my %idsbycluster;
    my %reposts;

    my @items = LJ::get_friend_items({
        'u'                 => $u,
        'userid'            => $u->{'userid'},
        'remote'            => $remote,
        'itemshow'          => $itemshow,
        'skip'              => $skip,
        'filter'            => $filter,
        'common_filter'     => $common_filter,
        'friends_u'         => \%friends,
        'friends'           => \%friends_row,
        'idsbycluster'      => \%idsbycluster,
        'showtypes'         => $get->{'show'},
        'friendsoffriends'  => $opts->{'view'} eq "friendsfriends",
        'dateformat'        => 'S2',
        'events_date'       => $events_date,
        'filter_by_tags'    => ($get->{notags} ? 0 : 1),
        'preload_props'     => 1,
    });

    # warn "[FriendsPage=$user] Items loaded. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    while ($_ = each %friends) {
        # we expect fgcolor/bgcolor to be in here later
        $friends{$_}->{'fgcolor'} = $friends_row{$_}->{'fgcolor'} || '#ffffff';
        $friends{$_}->{'bgcolor'} = $friends_row{$_}->{'bgcolor'} || '#000000';
    }

    return $p unless %friends;

    ### load the log properties
    my %logprops = ();  # key is "$owneridOrZero $[j]itemid"
    LJ::load_log_props2multi(\%idsbycluster, \%logprops);

    # warn "[FriendsPage=$user] items props loaded. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    # load the text of the entries
    my $logtext = LJ::get_logtext2multi(\%idsbycluster);

    # warn "[FriendsPage=$user] items logtext2multi loaded. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    # load tags on these entries
    my $logtags = LJ::Tags::get_logtagsmulti(\%idsbycluster);

    # warn "[FriendsPage=$user] LJ::Tags::get_logtagsmulti loaded. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    my %posters;

    {
        my @posterids;

        foreach my $item (@items) {
            next if $friends{$item->{'posterid'}};
            push @posterids, $item->{'posterid'};
        }

        LJ::load_userids_multiple([ map { $_ => \$posters{$_} } @posterids ])
            if @posterids;
    }

    my %objs_of_picid;
    my @userpic_load;

    my %lite;   # posterid -> s2_UserLite

    my $get_lite = sub {
        my $id = shift;
        return $lite{$id} if $lite{$id};
        return $lite{$id} = UserLite($posters{$id} || $friends{$id});
    };

    my $eventnum      = 0;
    my $hiddenentries = 0;
    my $ljcut_disable = $remote ? $remote->{'opt_ljcut_disable_friends'} : undef;

    my $replace_images_in_friendspage = 0;
    my $replace_video = $remote ? $remote->opt_embedplaceholders : 0;

    if( $u->equals($remote) ) {
        $replace_images_in_friendspage = $remote->opt_placeholders_friendspage;
    }

  ENTRY:
    foreach my $item (@items) {
        my ($friendid, $posterid, $itemid, $security, $allowmask, $alldatepart) =
            map { $item->{$_} } qw(ownerid posterid itemid security allowmask alldatepart);

        my $fr = $friends{$friendid};
        $p->{'friends'}->{$fr->{'user'}} ||= Friend($fr);

        my $clusterid = $item->{'clusterid'}+0;
        my $datakey   = "$friendid $itemid";

        my $replycount = $logprops{$datakey}->{'replycount'};
        my $subject    = $logtext->{$datakey}->[0];
        my $text       = $logtext->{$datakey}->[1];

        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $text    =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$datakey}->{'unknown8bit'}) {
            LJ::item_toutf8($friends{$friendid}, \$subject, \$text, $logprops{$datakey});
        }

        my ($friend, $poster);
        $friend = $poster = $friends{$friendid}->{'user'};

        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $entry_obj = LJ::Entry->new($friends{$friendid}, ditemid => $ditemid);
        my $repost_entry_obj;
        my $removed;
        
        my $content =  { 'original_post_obj' => \$entry_obj,
                         'repost_obj'        => \$repost_entry_obj,
                         'ditemid'           => \$ditemid,
                         'itemid'            => \$itemid,
                         'journalid'         => \$friendid,
                         'posterid'          => \$posterid,
                         'security'          => \$security,
                         'allowmask'         => \$allowmask,
                         'event_raw'         => \$text,
                         'subject'           => \$subject,
                         'removed'           => \$removed,
                         'reply_count'       => \$replycount, };

        if (LJ::Entry::Repost->substitute_content( $entry_obj, $content )) {
            next ENTRY if $removed;
            next ENTRY unless $entry_obj->visible_to($remote);

            $friend   = $entry_obj->journal;
            $poster   = $entry_obj->poster;

            $posters{$posterid} = $poster;
            $friends{$friendid} = $friend;
            $datakey  = "repost $friendid $itemid";    

            if (!$reposts{$datakey}) {
                $reposts{$datakey} = 1;
            } else {
                $reposts{$datakey}++;
            }

            if (!$logprops{$datakey}) {
                $logprops{$datakey} = $entry_obj->props;
 
                # mark as repost
                $logprops{$datakey}->{'repost'}         = 'e';
                $logprops{$datakey}->{'repost_author'}  = $entry_obj->poster->user; 
                $logprops{$datakey}->{'repost_subject'} = $entry_obj->subject_html;
                $logprops{$datakey}->{'repost_url'}     = $entry_obj->url;
            }
        }

        if ( ($remote && 
              $logprops{$datakey}->{'repost'} && 
              $remote->prop('hidefriendsreposts') && 
              ! $remote->prop('opt_ljcut_disable_friends')) ||
              $reposts{$datakey} > 1 ) 
        {
            $text = LJ::Lang::ml(
                'friendsposts.reposted',
                {
                    'user'     => $logprops{$datakey}->{'repost_author'},
                    'subject'  => $logprops{$datakey}->{'repost_subject'},
                    'orig_url' => $logprops{$datakey}->{'repost_url'},
                    'url'      => $entry_obj->url,
            });
        }

        LJ::Entry->preload_props([$entry_obj]);

        my %urlopts_style;

        if (    $remote && $remote->{'opt_stylemine'}
             && $remote->{'userid'} != $friendid )
        {
            $urlopts_style{'style'} = 'mine';
        }

        my $suspend_msg = $entry_obj && $entry_obj->should_show_suspend_msg_to($remote) ? 1 : 0;

        LJ::CleanHTML::clean_event(
            \$text,
            {
                 'preformatted'        => $logprops{$datakey}->{'opt_preformatted'},
                 'cuturl'              => $entry_obj->url(%urlopts_style),
                 'entry_url'           => $entry_obj->url,
                 'ljcut_disable'       => $ljcut_disable,
                 'suspend_msg'         => $suspend_msg,
                 'unsuspend_supportid' => $suspend_msg ? $entry_obj->prop("unsuspend_supportid") : 0,
                 'journalid'           => $entry_obj->journalid,
                 'posterid'            => $entry_obj->posterid,
                 'img_placeholders'    => $replace_images_in_friendspage,
                 'video_placeholders'  => $replace_video,
        });

        LJ::expand_embedded(
            $friends{$friendid},
            $ditemid,
            $remote,
            \$text,
            'video_placeholders' => $replace_video,
        );

        $text = LJ::ContentFlag->transform_post(
            'post'    => $text,
            'journal' => $friends{$friendid},
            'remote'  => $remote,
            'entry'   => $entry_obj,
        );

        my $userlite_poster  = $get_lite->($posterid);
        my $userlite_journal = $get_lite->($friendid);

        # get the poster user
        my $po = $posters{$posterid} || $friends{$posterid};

        # don't allow posts from suspended users or suspended posts
        # or posts from users who chose to delete their entries when
        # they deleted their journals
        my $entry_hidden = 0;
        $entry_hidden ||= $po->is_suspended;
        $entry_hidden ||= $entry_obj && $entry_obj->is_suspended_for($remote);

        if ( $po->is_deleted
          && !$LJ::JOURNALS_WITH_PROTECTED_CONTENT{$po->username} )
        {
            my ($purge_comments, $purge_community_entries)
                = split /:/, $po->prop("purge_external_content");

            $entry_hidden ||= $purge_community_entries;
        }

        if ($entry_hidden) {
            $hiddenentries++; # Remember how many we've skipped for later
            next ENTRY;
        }

        my $eobj = LJ::Entry->new($friends{$friendid}, ditemid => $ditemid);
        $eobj->handle_prefetched_props($logprops{$datakey});

        # do the picture
        my $picid = 0;
        my $picu = undef;

        if ($friendid != $posterid && S2::get_property_value($opts->{ctx}, 'use_shared_pic')) {
            # using the community, the user wants to see shared pictures
            $picu = $friends{$friendid};

            # use shared pic for community
            $picid = $friends{$friendid}->{defaultpicid};
        }
        else {
            # we're using the poster for this picture
            $picu = $po;

            # check if they specified one
            $picid = $eobj->userpic ? $eobj->userpic->picid : 0;
        }

        my $journalbase = LJ::journal_base($friends{$friendid});
        my $permalink = $eobj->permalink_url;
        my $readurl   = $eobj->comments_url(%urlopts_style);
        my $posturl   = $eobj->reply_url(%urlopts_style);

        my $comments = CommentInfo({
            'read_url'    => $readurl,
            'post_url'    => $posturl,
            'count'       => $replycount,
            'maxcomments' => ($replycount >= LJ::get_cap($u, 'maxcomments')) ? 1 : 0,
            'enabled'     => $eobj->comments_shown,
            'locked'      => !$eobj->posting_comments_allowed,
            'screened'    => ($logprops{$datakey}->{'hasscreened'} && $remote &&
                               ($remote->{'user'} eq $fr->{'user'} || $remote->can_manage($fr))) ? 1 : 0,
        });

        $comments->{show_postlink} = $eobj->posting_comments_allowed;
        $comments->{show_readlink} = $eobj->comments_shown && ($replycount || $comments->{'screened'});

        my $moodthemeid = $u->{'opt_forcemoodtheme'} eq 'Y' ?
            $u->{'moodthemeid'} : $friends{$friendid}->{'moodthemeid'};

        my @taglist;

        while (my ($kwid, $kw) = each %{$logtags->{$datakey} || {}}) {
            push @taglist, Tag($friends{$friendid}, $kwid => $kw);
        }

        LJ::run_hooks('augment_s2_tag_list', u => $u, jitemid => $itemid, tag_list => \@taglist);
        @taglist = sort { $a->{name} cmp $b->{name} } @taglist;

        if ($opts->{enable_tags_compatibility} && @taglist) {
            $text .= LJ::S2::get_tags_text($opts->{ctx}, \@taglist);
        }

        if ($security eq "public" && !$LJ::REQ_GLOBAL{'text_of_first_public_post'}) {
            $LJ::REQ_GLOBAL{'text_of_first_public_post'} = $text;

            if (@taglist) {
                $LJ::REQ_GLOBAL{'tags_of_first_public_post'} = [map { $_->{name} } @taglist];
            }
        }

        my $entry = Entry($u, {
            'subject'           => $subject,
            'text'              => $text,
            'dateparts'         => $alldatepart,
            'system_dateparts'  => $item->{'system_alldatepart'},
            'security'          => $security,
            'allowmask'         => $allowmask,
            'props'             => $logprops{$datakey},
            'itemid'            => $ditemid,
            'journal'           => $userlite_journal,
            'poster'            => $userlite_poster,
            'comments'          => $comments,
            'new_day'           => 0,  # setup below
            'end_day'           => 0,  # setup below
            'userpic'           => undef,
            'tags'              => \@taglist,
            'permalink_url'     => $permalink,
            'moodthemeid'       => $moodthemeid,
            'real_journalid' => $repost_entry_obj ? $repost_entry_obj->journalid : undef,
            'real_itemid'    => $repost_entry_obj ? $repost_entry_obj->jitemid : undef,
        });

        $entry->{'_ymd'} = join('-', map { $entry->{'time'}->{$_} } qw(year month day));

        if ($picid && $picu) {
            push @userpic_load, [ $picu, $picid ];
            push @{$objs_of_picid{$picid}}, \$entry->{'userpic'};
        }

        push @{$p->{'entries'}}, $entry;
        $eventnum++;
        LJ::run_hook('notify_event_displayed', $eobj);
    } # end while

    # set the new_day and end_day members.
    if ($eventnum) {
        for (my $i = 0; $i < $eventnum; $i++) {
            my $entry = $p->{'entries'}->[$i];
            $entry->{'new_day'} = 1;
            my $last = $i;
            for (my $j = $i+1; $j < $eventnum; $j++) {
                my $ej = $p->{'entries'}->[$j];
                if ($ej->{'_ymd'} eq $entry->{'_ymd'}) {
                    $last = $j;
                }
            }
            $p->{'entries'}->[$last]->{'end_day'} = 1;
            $i = $last;
        }
    }

    # load the pictures that were referenced, then retroactively populate
    # the userpic fields of the Entries above
    my %userpics;
    LJ::load_userpics(\%userpics, \@userpic_load);

    # warn "[FriendsPage=$user] userpics loaded. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    foreach my $picid (keys %userpics) {
        my $up = Image("$LJ::USERPIC_ROOT/$picid/$userpics{$picid}->{'userid'}",
                       $userpics{$picid}->{'width'},
                       $userpics{$picid}->{'height'});
        foreach (@{$objs_of_picid{$picid}}) { $$_ = $up; }
    }

    # make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
        'count' => $eventnum,
    };

    # $linkfilter is distinct from $filter: if user has a default view,
    # $filter is now set according to it but we don't want it to show in the links.
    # $incfilter may be true even if $filter is 0: user may use filter=0 to turn
    # off the default group
    my $linkfilter = $get->{'filter'} + 0;
    my $incfilter = defined $get->{'filter'};

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my %linkvars;
        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;
        my $newskip = $skip - $itemshow;
        if ($newskip > 0) { $linkvars{'skip'} = $newskip; }
        else { $newskip = 0; }
        $linkvars{'date'} = $get->{date} if $get->{date};
        $nav->{'forward_url'} = LJ::make_link($base, \%linkvars);
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_count'} = $itemshow;
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown
    ## on the page, but who cares about that)
    # Must remember to count $hiddenentries or we'll have no skiplinks when > 1
    unless (($eventnum + $hiddenentries) != $itemshow || $skip == $maxskip) {
        my %linkvars;
        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;
        $linkvars{'date'} = $get->{'date'} if $get->{'date'};
        my $newskip = $skip + $itemshow;
        $linkvars{'skip'} = $newskip;
        $nav->{'backward_url'} = LJ::make_link($base, \%linkvars);
        $nav->{'backward_skip'} = $newskip;
        $nav->{'backward_count'} = $itemshow;
    }

    $p->{'nav'} = $nav;
    # warn "[FriendsPage=$user] page prepared. elapsed=" . Time::HiRes::tv_interval( $t0, [Time::HiRes::gettimeofday]) . " sec";

    return $p;
}

1;
