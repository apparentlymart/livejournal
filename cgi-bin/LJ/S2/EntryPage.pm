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
    
    my ($entry, $s2entry) = EntryPage_entry($u, $remote, $opts);
    return if $opts->{'handler_return'};

    $p->{'multiform_on'} = $remote &&
        ($remote->{'userid'} == $u->{'userid'} ||
         $remote->{'userid'} == $entry->{'posterid'} ||
         LJ::check_rel($u, $remote, 'A'));

    my $itemid = $entry->{'itemid'};
    my $ditemid = $entry->{'itemid'} * 256 + $entry->{'anum'};
    my $permalink = LJ::journal_base($u) . "/$ditemid.html";

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

    $p->{'entry'} = $s2entry;

    # add the comments
    my %userpic;
    my %user;
    my $copts = {
        'thread' => ($get->{'thread'} >> 8),
        'page' => $get->{'page'},
        'view' => $get->{'view'},
        'userpicref' => \%userpic,
        'userref' => \%user,
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
            LJ::CleanHTML::clean_comment(\$text, $com->{'props'}->{'opt_preformatted'});

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

            my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";
            my $reply_url = LJ::Talk::talkargs($permalink, "replyto=$dtalkid", $stylemine);

            my $par_url;
            if ($com->{'parenttalkid'}) {
                my $dparent = ($com->{'parenttalkid'} << 8) + $entry->{'anum'};
                $par_url = LJ::Talk::talkargs($permalink, "thread=$dparent", $stylemine);
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
                'full' => $com->{'_loaded'} ? 1 : 0,
                'depth' => $depth,
                'parent_url' => $par_url,
                'screened' => $com->{'state'} eq "S" ? 1 : 0,
                'link_keyseq' => [ 'delete_comment' ],
            };

            # don't show info from suspended users
            # FIXME: ideally the load_comments should only return these
            # items if there are children, otherwise they should be hidden entirely
            my $pu = $com->{'posterid'} ? $user{$com->{'posterid'}} : undef;
            if ($pu && $pu->{'statusvis'} eq "S") {
                $s2com->{'text'} = "";
                $s2com->{'subject'} = "";
                $s2com->{'full'} = 0;
                $s2com->{'subject_icon'} = undef;
                $s2com->{'userpic'} = undef;
            }

            # Conditionally add more links to the keyseq
            my $link_keyseq = $s2com->{'link_keyseq'};
            if ($s2com->{'screened'}) {
                push @$link_keyseq, 'unscreen_comment';
            } else {
                push @$link_keyseq, 'screen_comment';
            }

            if (@{$com->{'children'}}) {
                $s2com->{'thread_url'} = LJ::Talk::talkargs($permalink, "thread=$dtalkid", $stylemine);
            }                    

            # add the poster_ip metadata if remote user has 
            # access to see it.
            $s2com->{'metadata'}->{'poster_ip'} = $com->{'props'}->{'poster_ip'} if 
                ($com->{'props'}->{'poster_ip'} && $remote &&
                 ($remote->{'userid'} == $entry->{'posterid'} ||
                  LJ::check_rel($u, $remote, 'A')));
            
            push @$destlist, $s2com;

            $self->($self, $s2com->{'replies'}, $com->{'children'}, $depth+1);
        }
    };
    $p->{'comments'} = [];
    $convert_comments->($convert_comments, $p->{'comments'}, \@comments, 1);

    $p->{'viewing_thread'} = $get->{'thread'} ? 1 : 0;

    $p->{'comment_pages'} = ItemRange({
        'all_subitems_displayed' => ($copts->{'out_pages'} == 1),
        'current' => $copts->{'out_page'},
        'from_subitem' => $copts->{'out_itemfirst'},
        'num_subitems_displayed' => scalar @comments,
        'to_subitem' => $copts->{'out_itemlast'},
        'total' => $copts->{'out_pages'},
        'total_subitems' => $copts->{'out_items'},
        '_url_of' => sub { return "$permalink?page=" . int($_[0]); },
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

    # do they have the viewall priv?
    if ($get->{'viewall'} && LJ::check_priv($remote, "viewall")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "entry: $u->{'user'}");

        # do nothing, let them pass

    # check using normal rules
    } elsif (! LJ::can_view($remote, $entry)) {
        $opts->{'handler_return'} = 403;
        return;
    }
    
    my $replycount = $entry->{'replycount'};
    my $nc = "";
    $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

    my $stylemine = $get->{'style'} eq "mine" ? "style=mine" : "";

    my $userlite_journal = UserLite($u);
    my $userlite_poster = $userlite_journal;
    my $pu = $u;
    if ($entry->{'posterid'} != $entry->{'ownerid'}) {
        $pu = LJ::load_userid($entry->{'posterid'});
        $userlite_poster = UserLite($pu);
    }

    my $userpic = Image_userpic($pu, 0, $entry->{'props'}->{'picture_keyword'});

    my $permalink = LJ::journal_base($u) . "/$ditemid.html";
    my $readurl = LJ::Talk::talkargs($permalink, $nc, $stylemine);
    my $posturl = LJ::Talk::talkargs($permalink, "mode=reply", $stylemine);

    my $comments = CommentInfo({
        'read_url' => $readurl,
        'post_url' => $posturl,
        'count' => $replycount,
        'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! 
                      $entry->{'props'}->{'opt_nocomments'}) ? 1 : 0,
        'screened' => ($entry->{'props'}->{'hasscreened'} && 
                       ($remote->{'user'} eq $u->{'user'}|| LJ::check_rel($u, $remote, 'A'))) ? 1 : 0,
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
    LJ::expand_embedded($ditemid, $remote, \$entry->{'event'});

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
        'new_day' => 0,
        'end_day' => 0,
        'userpic' => $userpic,
        'permalink_url' => $permalink,
    });
    
    return ($entry, $s2entry);
}

1;
