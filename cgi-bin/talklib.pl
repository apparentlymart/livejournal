#!/usr/bin/perl
#
# <LJDEP>
# link: htdocs/userinfo.bml, htdocs/go.bml, htdocs/tools/memadd.bml, htdocs/editjournal.bml
# link: htdocs/tools/tellafriend.bml
# img: htdocs/img/btn_prev.gif, htdocs/img/memadd.gif, htdocs/img/btn_edit.gif
# img: htdocs/img/btn_next.gif, htdocs/img/btn_tellafriend.gif
# </LJDEP>

use strict;
package LJ::Talk;

sub get_subjecticons
{
    my %subjecticon;
    $subjecticon{'types'} = [ 'sm', 'md' ];
    $subjecticon{'lists'}->{'md'} = [
            { img => "md01_alien.gif",		w => 32,	h => 32 },
            { img => "md02_skull.gif",		w => 32,	h => 32 },
            { img => "md05_sick.gif",		w => 25,	h => 25 },
            { img => "md06_radioactive.gif",	w => 20,	h => 20 },
            { img => "md07_cool.gif",		w => 20,	h => 20 },
            { img => "md08_bulb.gif",		w => 17,	h => 23 },
            { img => "md09_thumbdown.gif",		w => 25,	h => 19 },
            { img => "md10_thumbup.gif",		w => 25,	h => 19 }
    ];
    $subjecticon{'lists'}->{'sm'} = [
            { img => "sm01_smiley.gif",		w => 15,	h => 15 },
            { img => "sm02_wink.gif",		w => 15,	h => 15 },
            { img => "sm03_blush.gif",		w => 15,	h => 15 },
            { img => "sm04_shock.gif",		w => 15,	h => 15 },
            { img => "sm05_sad.gif",		w => 15,	h => 15 },
            { img => "sm06_angry.gif",		w => 15,	h => 15 },
            { img => "sm07_check.gif",		w => 15,	h => 15 },
            { img => "sm08_star.gif",		w => 20,	h => 18 },
            { img => "sm09_mail.gif",		w => 14,	h => 10 },
            { img => "sm10_eyes.gif",		w => 24,	h => 12 }
    ];

    # assemble ->{'id'} portion of hash.  the part of the imagename before the _
    foreach (keys %{$subjecticon{'lists'}}) {
            foreach my $pic (@{$subjecticon{'lists'}->{$_}}) {
            next unless ($pic->{'img'} =~ /^(\D{2}\d{2})\_.+$/);
            $subjecticon{'pic'}->{$1} = $pic;
            $pic->{'id'} = $1;
            }
    }

    return \%subjecticon;
}

# Returns HTML to display an image, given the image id as an argument.
sub show_image
{
    my $pics = shift;
    my $id = shift;
    my $extra = shift;
    return unless defined $pics->{'pic'}->{$id};
    my $p = $pics->{'pic'}->{$id};
    my $pfx = "$LJ::IMGPREFIX/talk";
    return "<img src='$pfx/$p->{'img'}' border='0' ".
        "width='$p->{'w'}' height='$p->{'h'}' valign='middle' $extra />";
}

# Returns 'none' icon.
sub show_none_image
{
    my $extra = shift;
    my $img = 'none.gif';
    my $w = 15;
    my $h = 15;
    my $pfx = "$LJ::IMGPREFIX/talk";
    return "<img src='$pfx/$img' border='0' ".
        "width='$w' height='$h' valign='middle' $extra />";
}

sub link_bar
{
    my $opts = shift;
    my ($u, $up, $remote, $headref, $itemid) = 
        map { $opts->{$_} } qw(u up remote headref itemid);
    my $ret;

    my @linkele;
    
    my $mlink = sub {
        my ($url, $piccode) = @_;
        return ("<a href=\"$url\">" . 
                LJ::img($piccode, "", { 'align' => 'absmiddle' }) .
                "</a>");
    };

    my $jarg = "journal=$u->{'user'}&";
    my $jargent = "journal=$u->{'user'}&amp;";

    # << Previous
    push @linkele, $mlink->("/go.bml?${jargent}itemid=$itemid&amp;dir=prev", "prev_entry");
    $$headref .= "<link href='/go.bml?${jargent}itemid=$itemid&amp;dir=prev' rel='Previous' />\n";
    
    # memories
    unless ($LJ::DISABLED{'memories'}) {
        push @linkele, $mlink->("/tools/memadd.bml?${jargent}itemid=$itemid", "memadd");
    }
    
    if (defined $remote && ($remote->{'user'} eq $u->{'user'} ||
                            $remote->{'user'} eq $up->{'user'} || 
                            LJ::check_rel($u, $remote, 'A')))
    {
        push @linkele, $mlink->("/editjournal_do.bml?${jargent}itemid=$itemid", "editentry");
    }
    
    unless ($LJ::DISABLED{'tellafriend'}) {
        push @linkele, $mlink->("/tools/tellafriend.bml?${jargent}itemid=$itemid", "tellfriend");
    }
    
    ## >>> Next
    push @linkele, $mlink->("/go.bml?${jargent}itemid=$itemid&amp;dir=next", "next_entry");
    $$headref .= "<link href='/go.bml?${jargent}itemid=$itemid&amp;dir=next' rel='Next' />\n";
    
    if (@linkele) {
        $ret .= BML::fill_template("standout", {
            'DATA' => "<table><tr><td valign='middle'>" .
                join("&nbsp;&nbsp;", @linkele) . 
                "</td></tr></table>",
            });
    }

    return $ret;
}

sub init 
{
    my ($form) = @_;
    my $init = {};  # structure to return

    my $journal = $form->{'journal'};
    my $ju = undef;
    my $item = undef;        # hashref; journal item conversation is in

    # defaults, to be changed later:
    $init->{'itemid'} = $form->{'itemid'}+0;
    $init->{'clustered'} = 0;
    $init->{'replyto'} = $form->{'replyto'}+0;
    $init->{'ditemid'} = $init->{'itemid'};
    $init->{'thread'} = $form->{'thread'}+0;
    
    if ($journal) {
        # they specified a journal argument, which indicates new style.
        $ju = LJ::load_user($journal);
        return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
        return { 'error' => BML::ml('talk.error.bogusargs')} unless $ju->{'clusterid'};
        $init->{'clustered'} = 1;
        foreach (qw(itemid replyto)) {
            next unless $init->{$_};
            $init->{'anum'} = $init->{$_} % 256;
            $init->{$_} = int($init->{$_} / 256);
            last;
        }
        $init->{'thread'} = int($init->{'thread'} / 256)
            if $init->{'thread'};
    } else {
        # perhaps it's an old URL for a user that's since been clustered.
        # look up the itemid and see what user it belongs to.
        if ($form->{'itemid'}) {
            my $itemid = $form->{'itemid'}+0;
            my $newinfo = LJ::get_newids('L', $itemid);
            if ($newinfo) {
                $ju = LJ::load_userid($newinfo->[0]);
                $init->{'clustered'} = 1;
                $init->{'itemid'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
                if ($form->{'thread'}) {
                    my $tinfo = LJ::get_newids('T', $init->{'thread'});
                    $init->{'thread'} = $tinfo->[1] if $tinfo;
                }
            } else {
                return { 'error' => BML::ml('talk.error.noentry') };
            }
        } elsif ($form->{'replyto'}) {
            my $replyto = $form->{'replyto'}+0;
            my $newinfo = LJ::get_newids('T', $replyto);
            if ($newinfo) {
                $ju = LJ::load_userid($newinfo->[0]);
                $init->{'replyto'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
            } else {
                return { 'error' => BML::ml('talk.error.noentry') };
            }
        }
    }

    $init->{'journalu'} = $ju;
    return $init;
}

# dbs?, dbcs?, $u, $itemid
sub get_journal_item
{
    my $dbs = ref $_[0] eq "LJ::DBSet" ? shift : undef;
    my $dbcs = ref $_[0] eq "LJ::DBSet" ? shift : undef;
    my ($u, $itemid) = @_;

    my $uid = $u->{'userid'}+0;
    $itemid += 0;

    my $s2datefmt = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    my $sql = "SELECT journalid, posterid, eventtime, security, allowmask, anum, ".
        "DATE_FORMAT(eventtime, '${s2datefmt}') AS 'alldatepart', ".
        "UNIX_TIMESTAMP()-UNIX_TIMESTAMP(logtime) AS 'secondsold' ".
        "FROM log2 WHERE journalid=$uid AND jitemid=$itemid";

    my $item;
    my $dbc;
    foreach my $role ("slave", "master") {
        next if $item;
        $dbc = $role eq "slave" ? LJ::get_cluster_reader($u) : LJ::get_cluster_master($u);
        $item = $dbc->selectrow_hashref($sql);
    }
    return undef unless $item;

    $item->{'itemid'} = $item->{'jitemid'} = $itemid;   # support old & new keys
    $item->{'ownerid'} = $item->{'journalid'};          # support old & news keys

    my $lt = LJ::get_logtext2($u, $itemid);
    my $v = $lt->{$itemid};
    $item->{'subject'} = $v->[0];
    $item->{'event'} = $v->[1];

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2($dbc, $u->{'userid'}, [ $itemid ], \%logprops);
    $item->{'props'} = $logprops{$itemid} || {};

    if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
        LJ::item_toutf8($u, \$item->{'subject'}, \$item->{'event'},
                        $item->{'logprops'}->{$itemid});
    }
    return $item;
}

sub check_viewable
{
    shift @_ if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db"; 
    my ($remote, $item, $form, $errref) = @_;
    
    my $err = sub {
        $$errref = "<?h1 <?_ml Error _ml?> h1?><?p $_[0] p?>";
        return 0;
    };

    my $dbr = LJ::get_db_reader();
    unless (LJ::can_view($dbr, $remote, $item)) 
    {
        if ($form->{'viewall'} && LJ::check_priv($dbr, $remote, "viewall")) {
            LJ::statushistory_add($item->{'posterid'}, $remote->{'userid'}, 
                                  "viewall", "itemid = $item->{'itemid'}");
        } else {
            return $err->(BML::ml('talk.error.mustlogin'))
                unless defined $remote;
            return $err->(BML::ml('talk.error.notauthorised'));
        }
    }

    return 1;
}

sub can_delete {
    shift @_ if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db"; 
    my ($remote, $u, $up, $userpost) = @_; # remote, journal, posting user, commenting user
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $userpost ||
                $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                LJ::check_rel($u, $remote, 'A');
    return 0;
}

sub can_screen {
    shift @_ if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db"; 
    my ($remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                LJ::check_rel($u, $remote, 'A');
    return 0;
}

sub can_unscreen {
    return LJ::Talk::can_screen(@_);
}

sub can_view_screened {
    return LJ::Talk::can_delete(@_);
}

sub update_commentalter {
    my ($u, $itemid) = @_;
    LJ::set_logprop($u, $itemid, { 'commentalter' => time() });
}

sub screen_comment {
    my $u = shift;
    my $itemid = shift(@_) + 0;
    my $dbcm = LJ::get_cluster_master($u);

    my $in = join (',', map { $_+0 } @_);
    return unless $in;

    my $userid = $u->{'userid'} + 0;

    my $updated = $dbcm->do("UPDATE talk2 SET state='S' ".
                            "WHERE journalid=$userid AND jtalkid IN ($in) ".
                            "AND nodetype='L' AND nodeid=$itemid ".
                            "AND state NOT IN ('S','D')");
    if ($updated > 0) {
        $dbcm->do("UPDATE log2 SET replycount=replycount-$updated WHERE journalid=$userid AND jitemid=$itemid");
        LJ::set_logprop($u, $itemid, { 'hasscreened' => 1 });
    }

    LJ::Talk::update_commentalter($u, $itemid);
    return;
}

sub unscreen_comment {
    my $u = shift;
    my $itemid = shift(@_) + 0;
    my $dbcm = LJ::get_cluster_master($u);

    my $in = join (',', map { $_+0 } @_);
    return unless $in;

    my $userid = $u->{'userid'} + 0;
    my $prop = LJ::get_prop("log", "hasscreened");

    my $updated = $dbcm->do("UPDATE talk2 SET state='A' ".
                            "WHERE journalid=$userid AND jtalkid IN ($in) ".
                            "AND nodetype='L' AND nodeid=$itemid ".
                            "AND state='S'");
    if ($updated > 0) {
        $dbcm->do("UPDATE log2 SET replycount=replycount+$updated WHERE journalid=$userid AND jitemid=$itemid");
        
        my $hasscreened = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 " .
                                                 "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='S'");
        LJ::set_logprop($u, $itemid, { 'hasscreened' => 0 }) unless $hasscreened;
    }

    LJ::Talk::update_commentalter($u, $itemid);
    return;
}

# LJ::Talk::load_comments($u, $remote, $nodetype, $nodeid, $opts)
#
# nodetype: "L" (for log) ... nothing else has been used
# noteid: the jitemid for log.
# opts keys:
#   thread -- jtalkid to thread from ($init->{'thread'} or $GET{'thread'} >> 8)
#   page -- $GET{'page'}
#   view -- $GET{'view'} (picks page containing view's ditemid)
#   up -- [optional] hashref of user object who posted the thing being replied to
#         only used to make things visible which would otherwise be screened?
#   out_error -- set by us if there's an error code:
#        nodb:  database unavailable
#        noposts:  no posts to load
#   out_pages:  number of pages
#   out_page:  page number being viewed
#   out_itemfirst:  first comment number on page (1-based, not db numbers)
#   out_itemlast:  last comment number on page (1-based, not db numbers)
#   out_pagesize:  size of each page
#   out_items:  number of total top level items
#
#   userpicref -- hashref to load userpics into, or undef to
#                 not load them.
#   userref -- hashref to load users into, keyed by userid
#
# returns:
#   array of hashrefs containing keys:
#      - talkid (jtalkid)
#      - posterid (or zero for anon)
#      - userpost (string, or blank if anon)
#      - datepost (mysql format)
#      - parenttalkid (or zero for top-level)
#      - state ("A"=approved, "S"=screened, "D"=deleted stub)
#      - userpic number
#      - picid   (if userpicref AND userref were given)
#      - _loaded => 1 (if fully loaded, subject & body)
#      - subject
#      - body
#      - props => { propname => value, ... }
#      - children => [ hashrefs like these ]
#
#      also present, but don't rely on:
#      - _show => {0|1}, if item is to be ideally shown (0 if deleted or screened)
#        unknown items will never be _loaded
sub load_comments
{
    my ($u, $remote, $nodetype, $nodeid, $opts) = @_;

    my $n = $u->{'clusterid'};
    my $db = LJ::get_dbh("cluster${n}lite", "cluster${n}slave", "cluster$n");
    my $dbcr = LJ::get_cluster_reader($u);
    unless ($db) {
        $opts->{'out_error'} = "nodb";
        return;
    }

    my $sth;
    $sth = $db->prepare("SELECT t.jtalkid AS 'talkid', t.posterid, u.user AS 'userpost', ".
                        "t.datepost, t.parenttalkid, t.state ".
                        "FROM talk2 t ".
                        "LEFT JOIN useridmap u ON u.userid=t.posterid ".
                        "WHERE t.journalid=? AND t.nodetype=? ".
                        "AND t.nodeid=?");
    $sth->execute($u->{'userid'}, $nodetype, $nodeid);

    my %users_to_load;
    my @posts_to_load;
    my %posts;          # talkid -> talk2 row hashref (mutated as above)
    my %children;       # talkid -> [ childenids+ ]

    my $uposterid = $opts->{'up'} ? $opts->{'up'}->{'userid'} : 0;

    my $post_count = 0;
    {
        $posts{$_->{'talkid'}} = $_ while $_ = $sth->fetchrow_hashref;
        my %showable_children;  # $id -> $count

        foreach my $post (sort { $b->{'talkid'} <=> $a->{'talkid'} } values %posts) {
            # see if we should ideally show it or not.  even if it's 
            # zero, we'll still show it if a child of it 
            my $should_show = 1; 
            $should_show = 0 if
                $post->{'state'} eq "D" ||
                ($post->{'state'} eq "S" && ! ($remote && ($remote->{'userid'} == $u->{'userid'} ||
                                                           $remote->{'userid'} == $uposterid ||
                                                           $remote->{'userid'} == $post->{'posterid'} ||
                                                           LJ::check_rel($u, $remote, 'A') )));
            $post->{'_show'} = $should_show;
            $post_count += $should_show;

            # make any post top-level if it says it has a parent but it isn't 
            # loaded yet which means either a) row in database is gone, or b)
            # somebody maliciously/accidentally made their parent be a future
            # post, which could result in an infinite loop, which we don't want.
            $post->{'parenttalkid'} = 0 
                if $post->{'parenttalkid'} && ! $posts{$post->{'parenttalkid'}};

            $post->{'children'} = [ map { $posts{$_} } @{$children{$post->{'talkid'}} || []} ];

            # increment the parent post's number of showable children,
            # which is our showability plus all those of our children
            # which were already computed, since we're working new to old
            # and children are always newer.
            # then, if we or our children are showable, add us to the child list
            my $sum = $should_show + $showable_children{$post->{'talkid'}};
            if ($sum) {
                $showable_children{$post->{'parenttalkid'}} += $sum;
                unshift @{$children{$post->{'parenttalkid'}}}, $post->{'talkid'};
            }
        }
    }

    # with a wrong thread number, silently default to the whole page
    my $thread = $opts->{'thread'}+0;
    $thread = 0 unless $posts{$thread};

    unless ($thread || $children{$thread}) {
        $opts->{'out_error'} = "noposts";
        return;
    }

    my $page_size = $LJ::TALK_PAGE_SIZE || 25;
    my $threading_point = $LJ::TALK_THREAD_POINT || 50;

    # we let the page size initially get bigger than normal for awhile,
    # but if it passes threading_point, then everything's in page_size
    # chunks:
    $page_size = $threading_point if $post_count < $threading_point;
    
    my $top_replies = $thread ? 1 : scalar(@{$children{$thread}});
    my $pages = int($top_replies / $page_size);
    if ($top_replies % $page_size) { $pages++; }
    
    my @top_replies = $thread ? ($thread) : @{$children{$thread}};
    my $page_from_view = 0;
    if ($opts->{'view'} && !$opts->{'page'}) {
        # find top-level comment that this comment is under
        my $viewid = $opts->{'view'} >> 8;
        while ($posts{$viewid} && $posts{$viewid}->{'parenttalkid'}) {
            $viewid = $posts{$viewid}->{'parenttalkid'};
        }
        for (my $ti = 0; $ti < @top_replies; ++$ti) {
            if ($posts{$top_replies[$ti]}->{'talkid'} == $viewid) {
                $page_from_view = int($ti/$page_size)+1;
                last;
            }
        }
    }
    my $page = int($opts->{'page'}) || $page_from_view || 1;
    $page = $page < 1 ? 1 : $page > $pages ? $pages : $page;
    
    my $itemfirst = $page_size * ($page-1) + 1;
    my $itemlast = $page==$pages ? $top_replies : ($page_size * $page);
    
    @top_replies = @top_replies[$itemfirst-1 .. $itemlast-1];
    
    push @posts_to_load, @top_replies;
    
    # mark child posts of the top-level to load, deeper
    # and deeper until we've hit the page size.  if too many loaded,
    # just mark that we'll load the subjects;
    my @check_for_children = @posts_to_load;
    my @subjects_to_load;
    while (@check_for_children) {
        my $cfc = shift @check_for_children;
        next unless defined $children{$cfc};
        foreach my $child (@{$children{$cfc}}) {
            if (@posts_to_load < $page_size) {
                push @posts_to_load, $child;
            } else {
                push @subjects_to_load, $child;
            }
            push @check_for_children, $child;
        }
    }

    $opts->{'out_pages'} = $pages;
    $opts->{'out_page'} = $page;
    $opts->{'out_itemfirst'} = $itemfirst;
    $opts->{'out_itemlast'} = $itemlast;
    $opts->{'out_pagesize'} = $page_size;
    $opts->{'out_items'} = $top_replies;
    
    # load text of posts
    my ($posts_loaded, $subjects_loaded);
    $posts_loaded = LJ::get_talktext2($u, @posts_to_load);
    $subjects_loaded = LJ::get_talktext2($u, {'onlysubjects'=>1}, @subjects_to_load) if @subjects_to_load;
    foreach my $talkid (@posts_to_load) {
        next unless $posts{$talkid}->{'_show'};
        $posts{$talkid}->{'_loaded'} = 1;
        $posts{$talkid}->{'subject'} = $posts_loaded->{$talkid}->[0];
        $posts{$talkid}->{'body'} = $posts_loaded->{$talkid}->[1];
        $users_to_load{$posts{$talkid}->{'posterid'}} = 1;
    }
    foreach my $talkid (@subjects_to_load) {
        next unless $posts{$talkid}->{'_show'};
        $posts{$talkid}->{'subject'} = $subjects_loaded->{$talkid}->[0];
    }

    # load meta-data
    {
        my %props;
        LJ::load_talk_props2($dbcr, $u->{'userid'}, \@posts_to_load, \%props);
        foreach (keys %props) {
            next unless $posts{$_}->{'_show'};
            $posts{$_}->{'props'} = $props{$_};
        }
    }

    if ($LJ::UNICODE) {
        foreach (@posts_to_load) {
            if ($posts{$_}->{'props'}->{'unknown8bit'}) {
                LJ::item_toutf8($u, \$posts{$_}->{'subject'},
                                \$posts{$_}->{'body'},
                                {});
              }
        }
    }

    # optionally load users
    if (ref($opts->{'userref'}) eq "HASH") {
        my %userpics = ();
        delete $users_to_load{0};
        if (%users_to_load) {
            LJ::load_userids_multiple([ map { $_, \$opts->{'userref'}->{$_} } 
                                        keys %users_to_load ]);;
        }

        # optionally load userpics
        if (ref($opts->{'userpicref'}) eq "HASH") {
            my %load_pic;
            foreach my $talkid (@posts_to_load) {
                my $post = $posts{$talkid};
                my $kw;
                if ($post->{'props'} && $post->{'props'}->{'picture_keyword'}) {
                    $kw = $post->{'props'}->{'picture_keyword'};
                }
                my $pu = $opts->{'userref'}->{$post->{'posterid'}};
                my $id = LJ::get_picid_from_keyword($pu, $kw);
                $post->{'picid'} = $id;
                $load_pic{$id} = 1 if $id;
            }
            
            LJ::load_userpics($opts->{'userpicref'}, [ keys %load_pic ]);
        }
    }
    
    return map { $posts{$_} } @top_replies;
}

1;
