#!/usr/bin/perl
#

use strict;
package LJ::S2;

use LJ::TimeUtil;

sub EntryPage
{
    my ($u, $remote, $opts) = @_;
    my $get = $opts->{'getargs'};

    my $p = Page($u, $opts);
    $p->{'_type'} = "EntryPage";
    $p->{'view'} = "entry";
    $p->{'comment_pages'} = undef;
    $p->{'comments'} = [];
    $p->{'comment_pages'} = undef;

    # setup viewall options
    my ($viewall, $viewsome) = (0, 0);
    if ($get->{viewall} && LJ::check_priv($remote, 'canview', 'suspended')) {
        # we don't log here, as we don't know what entry we're viewing yet.  the logging
        # is done when we call EntryPage_entry below.
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    my ($entry, $s2entry) = EntryPage_entry($u, $remote, $opts);
    return if $opts->{'suspendeduser'};
    return if $opts->{'suspendedentry'};
    return if $opts->{'readonlyremote'};
    return if $opts->{'readonlyjournal'};
    return if $opts->{'handler_return'};
    return if $opts->{'redir'};

    $p->{'multiform_on'} = $entry->comments_manageable_by($remote);

    my $itemid = $entry->jitemid;
    my $permalink = $entry->url;
    my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";
    my $style_set = defined $get->{'s2id'} ? "s2id=" . int( $get->{'s2id'} ) : "";
    my $style_arg = ($stylemine ne '' and $style_set ne '') ? ($stylemine . '&' . $style_set) : ($stylemine . $style_set);

    if ($u->should_block_robots || $entry->should_block_robots) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\" />\n";
    }

    # quickreply js libs
    LJ::need_res(qw(
                    js/basic.js
                    js/json.js
                    js/template.js
                    js/ippu.js
                    js/lj_ippu.js
                    js/userpicselect.js
                    js/hourglass.js
                    js/inputcomplete.js
                    stc/ups.css
                    stc/lj_base.css
                    js/datasource.js
                    js/selectable_table.js
                    )) if ! $LJ::DISABLED{userpicselect} && $remote && $remote->get_cap('userpicselect');

    LJ::need_res(qw(
                    js/quickreply.js
                    js/thread_expander.js
                    ));

    $p->{'entry'} = $s2entry;
    LJ::run_hook('notify_event_displayed', $entry);

    # add the comments
    my $view_arg = $get->{'view'} || "";
    my $flat_mode = ($view_arg =~ /\bflat\b/);
    my $view_num = ($view_arg =~ /(\d+)/) ? $1 : undef;

    my %userpic;
    my %user;
    my $copts = {
        'flat' => $flat_mode,
        'thread' => int($get->{'thread'} / 256),
        'page' => $get->{'page'},
        'view' => $view_num,
        'userpicref' => \%userpic,
        'userref' => \%user,
        # user object is cached from call just made in EntryPage_entry
        'up' => LJ::load_user($s2entry->{'poster'}->{'username'}),
        'viewall' => $viewall,
        'expand_all' => $opts->{expand_all},
    };
    
    ## Expand all comments on page
    unless ($LJ::DISABLED{allow_expand_all_comments}){
        $copts->{expand_all} = 1 if $get->{expand} eq 'all';
    }

    my $userlite_journal = UserLite($u);

    my @comments;
    if ($entry->comments_shown) {
        @comments = LJ::Talk::load_comments($u, $remote, "L", $itemid, $copts);
    }

    my $tz_remote;
    if ($remote) {
        my $tz = $remote->prop("timezone");
        $tz_remote = $tz ? eval { DateTime::TimeZone->new( name => $tz); } : undef;
    }

    my $pics = LJ::Talk::get_subjecticons()->{'pic'};  # hashref of imgname => { w, h, img }
    my $convert_comments = sub {
        my ($self, $destlist, $srclist, $depth) = @_;

        foreach my $com (@$srclist) {
            my $pu = $com->{'posterid'} ? $user{$com->{'posterid'}} : undef;

            my $dtalkid = $com->{'talkid'} * 256 + $entry->anum;
            my $text = $com->{'body'};
            if ($get->{'nohtml'}) {
                # quote all non-LJ tags
                $text =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            }
            LJ::CleanHTML::clean_comment(\$text, { 'preformatted' => $com->{'props'}->{'opt_preformatted'},
                                                   'anon_comment' => (!$pu || $pu->{'journaltype'} eq 'I'),
                                               });

            # local time in mysql format to gmtime
            my $datetime = DateTime_unix($com->{'datepost_unix'});
            my $datetime_remote = $tz_remote ? DateTime_tz($com->{'datepost_unix'}, $tz_remote) : undef;
            my $seconds_since_entry = $com->{'datepost_unix'} - $entry->logtime_unix;
            my $datetime_poster = DateTime_tz($com->{'datepost_unix'}, $pu);

            my ($edited, $edit_url, $edittime, $edittime_remote, $edittime_poster);
            if ($com->{_loaded}) {
                my $comment = LJ::Comment->new($u, jtalkid => $com->{talkid});

                $edited = $comment->is_edited;
                $edit_url = LJ::Talk::talkargs($comment->edit_url, $style_arg);
                if ($edited) {
                    $edittime = DateTime_unix($comment->edit_time);
                    $edittime_remote = $tz_remote ? DateTime_tz($comment->edit_time, $tz_remote) : undef;
                    $edittime_poster = DateTime_tz($comment->edit_time, $pu);
                }
            }

            my $subject_icon = undef;
            if (my $si = $com->{'props'}->{'subjecticon'}) {
                my $pic = $pics->{$si};
                $subject_icon = Image("$LJ::IMGPREFIX/talk/$pic->{'img'}",
                                      $pic->{'w'}, $pic->{'h'}) if $pic;
            }

            my $comment_userpic;
            if (my $pic = $userpic{$com->{'picid'}}) {
                $comment_userpic = Image("$LJ::USERPIC_ROOT/$com->{'picid'}/$pic->{'userid'}",
                                         $pic->{'width'}, $pic->{'height'});
            }

            my $reply_url = LJ::Talk::talkargs($permalink, "replyto=$dtalkid", $style_arg);

            my $par_url;

            # in flat mode, promote the parenttalkid_actual
            if ($flat_mode) {
                $com->{'parenttalkid'} ||= $com->{'parenttalkid_actual'};
            }

            if ($com->{'parenttalkid'}) {
                my $dparent = ($com->{'parenttalkid'} * 256) + $entry->anum;
                $par_url = LJ::Talk::talkargs($permalink, "thread=$dparent", $style_arg) . "#t$dparent";
            }

            my $poster;
            if ($com->{'posterid'} && $pu) {
                $poster = UserLite($pu);
                $poster->{'_opt_side_alias'} = 1;
            }

            # Comment Posted Notice
            my ($last_talkid, $last_jid) = LJ::get_lastcomment();
            my $commentposted = "";
            $commentposted = 1
                 if ($last_talkid == $dtalkid && $last_jid == $remote->{'userid'});

            my $s2com = {
                '_type' => 'Comment',
                'journal' => $userlite_journal,
                'metadata' => {
                    'picture_keyword' => $com->{'props'}->{'picture_keyword'},
                },
                'permalink_url' => "$permalink?thread=$dtalkid#t$dtalkid",
                'reply_url' => $reply_url,
                'poster' => $poster,
                'replies' => [],
                'subject' => LJ::ehtml($com->{'subject'}),
                'subject_icon' => $subject_icon,
                'talkid' => $dtalkid,
                'text' => $text,
                'userpic' => $comment_userpic,
                'time' => $datetime,
                'system_time' => $datetime, # same as regular time for comments
                'edittime' => $edittime,
                'tags' => [],
                'full' => $com->{'_loaded'} ? 1 : 0,
                'depth' => $depth,
                'parent_url' => $par_url,
                'screened' => $com->{'state'} eq "S" ? 1 : 0,
                'frozen' => $com->{'state'} eq "F" || !$entry->posting_comments_allowed ? 1 : 0,
                'deleted' => $com->{'state'} eq "D" ? 1 : 0,
                'link_keyseq' => [ 'delete_comment' ],
                'anchor' => "t$dtalkid",
                'dom_id' => "ljcmt$dtalkid",
                'comment_posted' => $commentposted,
                'edited' => $edited ? 1 : 0,
                'time_remote' => $datetime_remote,
                'time_poster' => $datetime_poster,
                'seconds_since_entry' => $seconds_since_entry,
                'edittime_remote' => $edittime_remote,
                'edittime_poster' => $edittime_poster,
                'edit_url' => $edit_url,
            };

            # don't show info from suspended users, and from users who deleted their journals 
            # and choosed to delete their comments in other journals
            if (!$viewsome && $pu) {
                my $hide_comment;
                if ($pu->is_suspended) {
                    $hide_comment = 1;
                } elsif ($pu->is_deleted) {
                    my ($purge_comments, $purge_community_entries) = split /:/, $pu->prop("purge_external_content");
                    if ($purge_comments && !$LJ::JOURNALS_WITH_PROTECTED_CONTENT{ $u->{user} }) {
                        $hide_comment = 1;
                    }
                }
                
                if ($hide_comment) {
                    $s2com->{'text'} = "";
                    $s2com->{'subject'} = "";
                    $s2com->{'full'} = 0;
                    $s2com->{'subject_icon'} = undef;
                    $s2com->{'userpic'} = undef;
                }
            }

            # Conditionally add more links to the keyseq
            my $link_keyseq = $s2com->{'link_keyseq'};
            push @$link_keyseq, $s2com->{'screened'} ? 'unscreen_comment' : 'screen_comment';
            if ($entry->posting_comments_allowed) {
                push @$link_keyseq, $s2com->{'frozen'} ? 'unfreeze_thread' : 'freeze_thread';
            }
            push @$link_keyseq, "watch_thread" unless $LJ::DISABLED{'esn'};
            push @$link_keyseq, "unwatch_thread" unless $LJ::DISABLED{'esn'};
            push @$link_keyseq, "watching_parent" unless $LJ::DISABLED{'esn'};
            unshift @$link_keyseq, "edit_comment" if LJ::is_enabled("edit_comments");

            $s2com->{'thread_url'} = LJ::Talk::talkargs($permalink, "thread=$dtalkid", $style_arg) . "#t$dtalkid";

            # add the poster_ip metadata if remote user has
            # access to see it.
            $s2com->{'metadata'}->{'poster_ip'} = $com->{'props'}->{'poster_ip'} if
                ($com->{'props'}->{'poster_ip'} && $remote &&
                 ($remote->{'userid'} == $entry->posterid ||
                  LJ::can_manage($remote, $u) || $viewall));

            push @$destlist, $s2com;

            $self->($self, $s2com->{'replies'}, $com->{'children'}, $depth+1);
        }
    };
    $p->{'comments'} = [];
    $convert_comments->($convert_comments, $p->{'comments'}, \@comments, 1);

    # prepare the javascript data structure to put in the top of the page
    # if the remote user is a manager of the comments
    my $do_commentmanage_js = $p->{'multiform_on'};
    if ($LJ::DISABLED{'commentmanage'}) {
        if (ref $LJ::DISABLED{'commentmanage'} eq "CODE") {
            $do_commentmanage_js = $LJ::DISABLED{'commentmanage'}->($remote);
        } else {
            $do_commentmanage_js = 0;
        }
    }

    # print comment info
    {
        my $canAdmin = LJ::can_manage($remote, $u) ? 1 : 0;
        my $formauth = LJ::ejs(LJ::eurl(LJ::form_auth(1)));

        my $cmtinfo = {
            form_auth => $formauth,
            journal   => $u->user,
            canAdmin  => $canAdmin,
            remote    => $remote ? $remote->user : undef,
        };

        my $recurse = sub {
            my ($self, $array) = @_;

            foreach my $i (@$array) {
                my $cmt = LJ::Comment->new($u, dtalkid => $i->{talkid});

                my $has_threads = scalar @{$i->{'replies'}};
                my $poster = $i->{'poster'} ? $i->{'poster'}{'username'} : "";
                my @child_ids = map { $_->{'talkid'} } @{$i->{'replies'}};
                my $parent = $cmt->parent;
                $cmtinfo->{$i->{talkid}} = {
                    rc     => \@child_ids,
                    u      => $poster,
                    parent => $parent && $parent->valid ? $parent->dtalkid : undef,
                    full   => ($i->{full}),
                };
                $self->($self, $i->{'replies'}) if $has_threads;
            }
        };

        $recurse->($recurse, $p->{'comments'});

        my $js = "<script>\n// don't crawl this.  read http://www.livejournal.com/developer/exporting.bml\n";
        $js .= "var LJ_cmtinfo = " . LJ::js_dumper($cmtinfo) . "\n";
        $js .= '</script>';
        $p->{'LJ_cmtinfo'} = $js if $opts->{'need_cmtinfo'};
        $p->{'head_content'} .= $js;
    }

    LJ::need_res(qw(
                    js/commentmanage.js
                    ));

    $p->{'_stylemine'} = $get->{'style'} eq 'mine' ? 1 : 0;
    $p->{'_picture_keyword'} = $get->{'prop_picture_keyword'};

    $p->{'viewing_thread'} = $get->{'thread'} ? 1 : 0;

    # default values if there were no comments, because
    # LJ::Talk::load_comments() doesn't provide them.
    if ($copts->{'out_error'} eq 'noposts' || scalar @comments < 1) {
        $copts->{'out_pages'} = $copts->{'out_page'} = 1;
        $copts->{'out_items'} = 0;
        $copts->{'out_itemfirst'} = $copts->{'out_itemlast'} = undef;
    }

    $p->{'comment_pages'} = ItemRange({
        'all_subitems_displayed' => ($copts->{'out_pages'} == 1),
        'current' => $copts->{'out_page'},
        'from_subitem' => $copts->{'out_itemfirst'},
        'num_subitems_displayed' => scalar @comments,
        'to_subitem' => $copts->{'out_itemlast'},
        'total' => $copts->{'out_pages'},
        'total_subitems' => $copts->{'out_items'},
        '_url_of' => sub {
            my $sty = $flat_mode ? "view=flat&" : "";
            return "$permalink?${sty}page=" . int($_[0]) .
                ($style_arg ? "&$style_arg" : '');
        },
    });

    return $p;
}

sub EntryPage_entry
{
    my ($u, $remote, $opts) = @_;

    my $get = $opts->{'getargs'};

    my $uri = LJ::Request->uri;

    my ($ditemid, $itemid);
    my $entry = $opts->{ljentry};  # only defined in named-URI case.  otherwise undef.

    unless ($entry || $uri =~ /(\d+)\.html/) {
        $opts->{'handler_return'} = 404;
        LJ::Request->pnotes ('error' => 'e404');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return;
    }

    $entry ||= LJ::Entry->new($u, ditemid => $1);

    unless ($entry->correct_anum) {
        $opts->{'handler_return'} = 404;
        LJ::Request->pnotes ('error' => 'e404');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return;
    }

    $ditemid = $entry->ditemid;
    $itemid  = $entry->jitemid;

    my $pu = $entry->poster;

    my $userlite_journal = UserLite($u);
    my $userlite_poster  = UserLite($pu);

    # do they have the viewall priv?
    my $canview = $get->{'viewall'} && LJ::check_priv($remote, "canview");
    my ($viewall, $viewsome) = (0, 0);
    if ($canview) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                              "viewall", "entry: $u->{'user'}, itemid: $itemid, statusvis: $u->{'statusvis'}");
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    # check using normal rules
    unless ($entry->visible_to($remote, $canview)) {
        if ($remote) {
            $opts->{'handler_return'} = 403;
            LJ::Request->pnotes ('error' => 'private');
            LJ::Request->pnotes ('remote' => LJ::get_remote());
            return;
        } else {
            my $host = LJ::Request->header_in("Host");
            my $args = scalar LJ::Request->args;
            my $querysep = $args ? "?" : "";
            my $redir = LJ::eurl("http://$host$uri$querysep$args");
            $opts->{'redir'} = "$LJ::SITEROOT/?returnto=$redir&errmsg=notloggedin";
            return;
        }
    }

    if (($pu && $pu->{'statusvis'} eq 'S') && !$viewsome) {
        $opts->{'suspendeduser'} = 1;
        LJ::Request->pnotes ('error' => 'suspended');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return;
    }

    if ($entry && $entry->is_suspended_for($remote)) {
        $opts->{'suspendedentry'} = 1;
        LJ::Request->pnotes ('error' => 'suspended');
        LJ::Request->pnotes ('remote' => LJ::get_remote());
        return;
    }

    my $replycount = $entry->prop("replycount");
    my $nc = "";
    $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

    my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";
    my $style_set = defined $get->{'s2id'} ? "s2id=" . int( $get->{'s2id'} ) : "";
    my $style_arg = ($stylemine ne '' and $style_set ne '') ? ($stylemine . '&' . $style_set) : ($stylemine . $style_set);

    my $userpic = Image_userpic($pu, $entry->userpic ? $entry->userpic->picid : 0);

    my $permalink = $entry->url;
    my $readurl = LJ::Talk::talkargs($permalink, $nc, $style_arg);
    my $posturl = LJ::Talk::talkargs($permalink, "mode=reply", $style_arg);

    my $comments = CommentInfo({
        'read_url' => $readurl,
        'post_url' => $posturl,
        'count' => $replycount,
        'maxcomments' => ($replycount >= LJ::get_cap($u, 'maxcomments')) ? 1 : 0,
        'enabled' => $entry->comments_shown,
        'locked' => !$entry->posting_comments_allowed,
        'screened' => ($entry->prop("hasscreened") && $remote &&
                       ($remote->{'user'} eq $u->{'user'} || LJ::can_manage($remote, $u))) ? 1 : 0,
    });
    $comments->{show_postlink} = $entry->posting_comments_allowed;
    $comments->{show_readlink} = $entry->comments_shown && ($replycount || $comments->{'screened'});

    # load tags
    my @taglist;
    {
        my $tag_map = $entry->tag_map;
        while (my ($kwid, $kw) = each %$tag_map) {
            push @taglist, Tag($u, $kwid => $kw);
        }
        LJ::run_hooks('augment_s2_tag_list', u => $u, jitemid => $itemid, tag_list => \@taglist);
        @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    }

    my $subject = $entry->subject_html;
    my $event = $entry->event_html;
    if ($get->{'nohtml'}) {
        # quote all non-LJ tags
        $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        $event   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
    }

    if ($opts->{enable_tags_compatibility} && @taglist) {
        $event .= LJ::S2::get_tags_text($opts->{ctx}, \@taglist);
    }

    if ($entry->security eq "public") {
        $LJ::REQ_GLOBAL{'text_of_first_public_post'} = $event;

        if (@taglist) {
            $LJ::REQ_GLOBAL{'tags_of_first_public_post'} = [map { $_->{name} } @taglist];
        }

        my @verticals = $entry->verticals_list_for_ad;
        if (@verticals) {
            $LJ::REQ_GLOBAL{'verticals_of_first_public_post'} = join(",", @verticals);
        }
    }

    my $s2entry = Entry($u, {
        'subject' => $subject,
        'text' => $event,
        'dateparts' => LJ::TimeUtil->alldatepart_s2($entry->eventtime_mysql),
        'system_dateparts' => LJ::TimeUtil->alldatepart_s2($entry->logtime_mysql),
        'security' => $entry->security,
        'allowmask' => $entry->allowmask,
        'props' => $entry->props,
        'itemid' => $ditemid,
        'comments' => $comments,
        'journal' => $userlite_journal,
        'poster' => $userlite_poster,
        'tags' => \@taglist,
        'new_day' => 0,
        'end_day' => 0,
        'userpic' => $userpic,
        'permalink_url' => $permalink,
    });

    return ($entry, $s2entry);
}

1;
