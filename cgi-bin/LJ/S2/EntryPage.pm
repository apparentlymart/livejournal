#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub EntryPage
{
    my ($u, $remote, $opts) = @_;

    my $ctx = $opts->{'ctx'};
    my $r = $opts->{'r'};
    my $uri = $r->uri;

    my %GET = $r->args;

    my $dbs = LJ::get_dbs();

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "EntryPage";
    $p->{'view'} = "entry";
    $p->{'comment_pages'} = undef;
    $p->{'comments'} = [];

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
    unless (LJ::can_view($dbs, $remote, $entry)) {
        $opts->{'handler_return'} = 403;
        return;
    }
    
    my $replycount = $entry->{'replycount'};
    my $nc = "";
    $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

    my $userlite_journal = UserLite($u);
    my $userlite_poster = $userlite_journal;
    my $pu = $u;
    if ($entry->{'posterid'} != $entry->{'ownerid'}) {
        $pu = LJ::load_userid($dbs, $entry->{'posterid'});
        $userlite_poster = UserLite($pu);
    }

    my $userpic = Image_userpic($pu, 0, $entry->{'props'}->{'picture_keyword'});

    my $jbase = LJ::journal_base($u);
    my $permalink = "$jbase/$ditemid.html";
    my $readurl = $permalink;
    $readurl .= "?$nc" if $nc;
    my $posturl = $permalink . "?mode=reply";

    my $comments = CommentInfo({
        'read_url' => $readurl,
        'post_url' => $posturl,
        'count' => $replycount,
        'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! 
                      $entry->{'props'}->{'opt_nocomments'}) ? 1 : 0,
        'screened' => ($entry->{'props'}->{'hasscreened'} && 
                       ($remote->{'user'} eq $u->{'user'}|| LJ::check_rel($dbs, $u, $remote, 'A'))) ? 1 : 0,
    });

    # format it
    LJ::CleanHTML::clean_subject(\$entry->{'subject'});
    LJ::CleanHTML::clean_event(\$entry->{'event'}, $entry->{'props'}->{'opt_preformatted'});
    LJ::expand_embedded($dbs, $ditemid, $remote, \$entry->{'event'});

    my $s2entry = Entry($u, {
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
    $p->{'entry'} = $s2entry;

    # add the comments
    my %userpic;
    my %user;
    my $copts = {
        'thread' => ($GET{'thread'} >> 8),
        'page' => $GET{'page'},
        'view' => $GET{'view'},
        'userpicref' => \%userpic,
        'userref' => \%user,
    };

    my @comments = LJ::Talk::load_comments($u, $remote, "L", $itemid, $copts);

    my $pics = LJ::Talk::get_subjecticons()->{'pic'};  # hashref of imgname => { w, h, img }
    my $convert_comments = sub {
        my ($self, $destlist, $srclist, $depth) = @_;

        foreach my $com (@$srclist) {
            my $dtalkid = $com->{'talkid'} * 256 + $entry->{'anum'};
            my $text = $com->{'body'};
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
                $comment_userpic = Image("$LJ::SITEROOT/userpic/$com->{'picid'}/$pic->{'userid'}",
                                         $pic->{'width'}, $pic->{'height'});
            }

            my $par_url;
            if ($com->{'parenttalkid'}) {
                my $dparent = ($com->{'parenttalkid'} << 8) + $entry->{'anum'};
                $par_url = "$jbase/$ditemid.html?thread=$dparent";
            }

            my $s2com = {
                '_type' => 'Comment',
                'journal' => $userlite_journal,
                'metadata' => {
                    'picture_keyword' => $com->{'props'}->{'picture_keyword'},
                },
                'permalink_url' => "$permalink?thread=$dtalkid#t$dtalkid",
                'reply_url' => "$permalink?replyto=$dtalkid",
                'poster' => $com->{'posterid'} ? UserLite($user{$com->{'posterid'}}) : undef,
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
            };

            $s2com->{'thread_url'} = "$permalink?thread=$dtalkid" if @{$com->{'children'}};

            # add the poster_ip metadata if remote user has 
            # access to see it.
            $s2com->{'metadata'}->{'poster_ip'} = $com->{'props'}->{'poster_ip'} if 
                ($com->{'props'}->{'poster_ip'} && $remote &&
                 ($remote->{'userid'} == $pu->{'userid'} ||
                  LJ::check_rel($dbs, $u, $remote, 'A')));
            
            push @$destlist, $s2com;

            $self->($self, $s2com->{'replies'}, $com->{'children'}, $depth+1);
        }
    };
    $p->{'comments'} = [];
    $convert_comments->($convert_comments, $p->{'comments'}, \@comments, 1);

    $p->{'viewing_thread'} = $GET{'thread'} ? 1 : 0;

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

1;
