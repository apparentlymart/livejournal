#!/usr/bin/perl
#

use strict;
package LJ::S2;

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
    if ($get->{viewall} && LJ::check_priv($remote, 'canview')) {
        # we don't log here, as we don't know what entry we're viewing yet.  the logging
        # is done when we call EntryPage_entry below.
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    my ($entry, $s2entry) = EntryPage_entry($u, $remote, $opts);
    return if $opts->{'suspendeduser'};
    return if $opts->{'handler_return'};

    $p->{'multiform_on'} = $remote &&
        ($remote->{'userid'} == $u->{'userid'} ||
         $remote->{'userid'} == $entry->{'posterid'} ||
         LJ::can_manage($remote, $u));

    my $itemid = $entry->{'itemid'};
    my $ditemid = $entry->{'itemid'} * 256 + $entry->{'anum'};
    my $permalink = LJ::journal_base($u) . "/$ditemid.html";
    my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/$ditemid.html" . $opts->{'pathextra'};
        return 1;
    }

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\" />\n";
    }

    # add the quickreply script library
    $p->{'head_content'} .= "<script>\nvar LJVAR;\n if (!LJVAR) LJVAR = new Object();\n";
    $p->{'head_content'} .= "LJVAR.siteroot = \"$LJ::SITEROOT\";\n</script>\n";
    $p->{'head_content'} .= $LJ::COMMON_CODE{'quickreply'};

    $p->{'entry'} = $s2entry;

    # add the comments
    my $view_arg = $get->{'view'} || "";
    my $flat_mode = ($view_arg =~ /\bflat\b/);
    my $view_num = ($view_arg =~ /(\d+)/) ? $1 : undef;

    my %userpic;
    my %user;
    my $copts = {
        'flat' => $flat_mode,
        'thread' => ($get->{'thread'} >> 8),
        'page' => $get->{'page'},
        'view' => $view_num,
        'userpicref' => \%userpic,
        'userref' => \%user,
        # user object is cached from call just made in EntryPage_entry
        'up' => LJ::load_user($s2entry->{'poster'}->{'username'}),
        'viewall' => $viewall,
    };

    my $userlite_journal = UserLite($u);

    my @comments = LJ::Talk::load_comments($u, $remote, "L", $itemid, $copts);

    my $pics = LJ::Talk::get_subjecticons()->{'pic'};  # hashref of imgname => { w, h, img }
    my $convert_comments = sub {
        my ($self, $destlist, $srclist, $depth) = @_;

        foreach my $com (@$srclist) {
            my $dtalkid = $com->{'talkid'} * 256 + $entry->{'anum'};
            my $text = $com->{'body'};
            if ($get->{'nohtml'}) {
                # quote all non-LJ tags
                $text =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            }
            LJ::CleanHTML::clean_comment(\$text, { 'preformatted' => $com->{'props'}->{'opt_preformatted'}, 
                                                   'anon_comment' => (!$com->{posterid}
                                                                      || (defined $user{$com->{posterid}}
                                                                          && $user{$com->{'posterid'}}->{'journaltype'}
                                                                          eq 'I'))
                                                   });

            # local time in mysql format to gmtime
            my $datetime = DateTime_unix(LJ::mysqldate_to_time($com->{'datepost'}));

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

            my $reply_url = LJ::Talk::talkargs($permalink, "replyto=$dtalkid", $stylemine);

            my $par_url;

            # in flat mode, promote the parenttalkid_actual
            if ($flat_mode) {
                $com->{'parenttalkid'} ||= $com->{'parenttalkid_actual'};
            }

            if ($com->{'parenttalkid'}) {
                my $dparent = ($com->{'parenttalkid'} << 8) + $entry->{'anum'};
                $par_url = LJ::Talk::talkargs($permalink, "thread=$dparent", $stylemine) . "#t$dparent";
            }

            my $poster;
            if ($com->{'posterid'}) {
                if ($user{$com->{'posterid'}}) {
                    $poster = UserLite($user{$com->{'posterid'}});
                } else {
                    $poster = {
                        '_type' => 'UserLite',
                        'username' => $com->{'userpost'},
                        'name' => $com->{'userpost'},  # we don't have this, so fake it
                        'journal_type' => 'P',         # fake too, but only people can post, so correct
                    };
                }
            }

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
                'tags' => [],
                'full' => $com->{'_loaded'} ? 1 : 0,
                'depth' => $depth,
                'parent_url' => $par_url,
                'screened' => $com->{'state'} eq "S" ? 1 : 0,
                'frozen' => $com->{'state'} eq "F" ? 1 : 0,
                'deleted' => $com->{'state'} eq "D" ? 1 : 0,
                'link_keyseq' => [ 'delete_comment' ],
                'anchor' => "t$dtalkid",
                'dom_id' => "ljcmt$dtalkid",
            };

            # don't show info from suspended users
            # FIXME: ideally the load_comments should only return these
            # items if there are children, otherwise they should be hidden entirely
            my $pu = $com->{'posterid'} ? $user{$com->{'posterid'}} : undef;
            if ($pu && $pu->{'statusvis'} eq "S" && !$viewsome) {
                $s2com->{'text'} = "";
                $s2com->{'subject'} = "";
                $s2com->{'full'} = 0;
                $s2com->{'subject_icon'} = undef;
                $s2com->{'userpic'} = undef;
            }

            # Conditionally add more links to the keyseq
            my $link_keyseq = $s2com->{'link_keyseq'};
            push @$link_keyseq, $s2com->{'screened'} ? 'unscreen_comment' : 'screen_comment';
            push @$link_keyseq, $s2com->{'frozen'} ? 'unfreeze_thread' : 'freeze_thread';

            if (@{$com->{'children'}}) {
                $s2com->{'thread_url'} = LJ::Talk::talkargs($permalink, "thread=$dtalkid", $stylemine) . "#t$dtalkid";
            }                    

            # add the poster_ip metadata if remote user has 
            # access to see it.
            $s2com->{'metadata'}->{'poster_ip'} = $com->{'props'}->{'poster_ip'} if 
                ($com->{'props'}->{'poster_ip'} && $remote &&
                 ($remote->{'userid'} == $entry->{'posterid'} ||
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

    if ($do_commentmanage_js) {
        my $js = "<script>\n// don't crawl this.  read http://www.livejournal.com/developer/exporting.bml\n";
        $js .= "var LJ_cmtinfo = {\n";
        my $canAdmin = LJ::can_manage($remote, $u) ? 1 : 0;
        $js .= "\tjournal: '$u->{user}',\n";
        $js .= "\tcanAdmin: $canAdmin,\n";
        $js .= "\tremote: '$remote->{user}',\n" if $remote;
        my $recurse = sub {
            my ($self, $array) = @_;
            foreach my $i (@$array) {
                my $has_threads = scalar @{$i->{'replies'}};
                my $poster = $i->{'poster'} ? $i->{'poster'}{'username'} : "";
                my $child_ids = join(',', map { $_->{'talkid'} } @{$i->{'replies'}});
                $js .= "\t$i->{'talkid'}: { rc: [$child_ids], u: '$poster' },\n";
                $self->($self, $i->{'replies'}) if $has_threads;
            }
        };
        $recurse->($recurse, $p->{'comments'});
        chop $js; chop $js;  # remove final ",\n".  stupid javascript.
        $js .= "\n};\n" .
            "var LJVAR;\n".
            "if (!LJVAR) LJVAR = new Object();\n".
            "LJVAR.imgprefix = \"$LJ::IMGPREFIX\";\n".
            "</script>\n";
        $p->{'head_content'} .= $js;
        $p->{'head_content'} .= "<script src='$LJ::SITEROOT/js/commentmanage.js'></script>\n";
        
    }


    $p->{'viewing_thread'} = $get->{'thread'} ? 1 : 0;

    # default values if there were no comments, because
    # LJ::Talk::load_comments() doesn't provide them.
    if ($copts->{'out_error'} eq 'noposts') {
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
                ($stylemine ? "&$stylemine" : '');
        },
    });

    return $p;
}

sub EntryPage_entry
{
    my ($u, $remote, $opts) = @_;

    my $get = $opts->{'getargs'};

    my $r = $opts->{'r'};
    my $uri = $r->uri;

    my ($ditemid, $itemid, $anum);
    unless ($uri =~ /(\d+)\.html/) {
        $opts->{'handler_return'} = 404;
        return;
    }

    $ditemid = $1;
    $anum = $ditemid % 256;
    $itemid = $ditemid >> 8;

    my $entry = LJ::Talk::get_journal_item($u, $itemid);
    unless ($entry && $entry->{'anum'} == $anum) {
        $opts->{'handler_return'} = 404;
        return;
    }

    my $userlite_journal = UserLite($u);
    my $userlite_poster = $userlite_journal;
    my $pu = $u;
    if ($entry->{'posterid'} != $entry->{'ownerid'}) {
        $pu = LJ::load_userid($entry->{'posterid'});
        $userlite_poster = UserLite($pu);
    }

    # do they have the viewall priv?
    my $viewall = 0;
    my $viewsome = 0;
    if ($get->{'viewall'} && LJ::check_priv($remote, "canview")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "entry: $u->{'user'}, itemid: $itemid, statusvis: $u->{'statusvis'}");
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    # check using normal rules
    unless (LJ::can_view($remote, $entry) || $viewall) {
        $opts->{'handler_return'} = 403;
        return;
    }
    if (($pu && $pu->{'statusvis'} eq 'S') && !$viewsome) {
        $opts->{'suspendeduser'} = 1;
        return;
    }

    my $replycount = $entry->{'props'}->{'replycount'};
    my $nc = "";
    $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

    my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";

    my $userpic = Image_userpic($pu, 0, $entry->{'props'}->{'picture_keyword'});

    my $permalink = LJ::journal_base($u) . "/$ditemid.html";
    my $readurl = LJ::Talk::talkargs($permalink, $nc, $stylemine);
    my $posturl = LJ::Talk::talkargs($permalink, "mode=reply", $stylemine);

    my $comments = CommentInfo({
        'read_url' => $readurl,
        'post_url' => $posturl,
        'count' => $replycount,
        'maxcomments' => ($replycount >= LJ::get_cap($u, 'maxcomments')) ? 1 : 0,
        'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! 
                      $entry->{'props'}->{'opt_nocomments'}) ? 1 : 0,
        'screened' => ($entry->{'props'}->{'hasscreened'} && $remote &&
                       ($remote->{'user'} eq $u->{'user'} || LJ::can_manage($remote, $u))) ? 1 : 0,
    });

    # format it
    if ($opts->{'getargs'}->{'nohtml'}) {
        # quote all non-LJ tags
        $entry->{'subject'} =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        $entry->{'event'}   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
    }
    my $raw_subj = $entry->{'subject'};
    LJ::CleanHTML::clean_subject(\$entry->{'subject'});
    LJ::CleanHTML::clean_event(\$entry->{'event'}, $entry->{'props'}->{'opt_preformatted'});
    LJ::expand_embedded($u, $ditemid, $remote, \$entry->{'event'});

    # load tags
    my @taglist;
    my $tags = LJ::Tags::get_logtags($u, $itemid);
    while (my ($kwid, $kw) = each %{$tags->{$itemid} || {}}) {
        push @taglist, Tag($u, $kwid => $kw);
    }
    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;

    if ($opts->{enable_tags_compatibility} && @taglist) {
        $entry->{event} .= LJ::S2::get_tags_text($opts->{ctx}, \@taglist);
    }

    my $s2entry = Entry($u, {
        '_rawsubject' => $raw_subj,
        'subject' => $entry->{'subject'},
        'text' => $entry->{'event'},
        'dateparts' => $entry->{'alldatepart'},
        'security' => $entry->{'security'},
        'props' => $entry->{'props'},
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
