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

# entryid-commentid-emailrecipientpassword hash
sub ecphash {
    my ($itemid, $talkid, $password) = @_;
    return "ecph-" . Digest::MD5::md5_hex($itemid . $talkid . $password);
}

# Returns talkurl with GET args added
sub talkargs {
    my $talkurl = shift;
    my $args = join("&", grep {$_} @_);
    my $sep;
    $sep = ($talkurl =~ /\?/ ? "&" : "?") if $args;
    return "$talkurl$sep$args";
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
    $init->{'ditemid'} = $init->{'itemid'};
    $init->{'thread'} = $form->{'thread'}+0;
    $init->{'dthread'} = $init->{'thread'};
    $init->{'clustered'} = 0;
    $init->{'replyto'} = $form->{'replyto'}+0;
    $init->{'style'} = $form->{'style'} ? "mine" : undef;
    
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
                return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
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
                return { 'error' => BML::ml('talk.error.nosuchjournal')} unless $ju;
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

# $u, $itemid
sub get_journal_item
{
    my ($u, $itemid) = @_;
    return unless $u && $itemid;

    my $uid = $u->{'userid'}+0;
    $itemid += 0;

    my $item = LJ::get_log2_row($u, $itemid);
    return undef unless $item;

    $item->{'alldatepart'} = LJ::alldatepart_s2($item->{'eventtime'});
    
    $item->{'itemid'} = $item->{'jitemid'};    # support old & new keys
    $item->{'ownerid'} = $item->{'journalid'}; # support old & news keys

    my $lt = LJ::get_logtext2($u, $itemid);
    my $v = $lt->{$itemid};
    $item->{'subject'} = $v->[0];
    $item->{'event'} = $v->[1];

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2($u->{'userid'}, [ $itemid ], \%logprops);
    $item->{'props'} = $logprops{$itemid} || {};

    if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
        LJ::item_toutf8($u, \$item->{'subject'}, \$item->{'event'},
                        $item->{'logprops'}->{$itemid});
    }
    return $item;
}

sub check_viewable
{
    my ($remote, $item, $form, $errref) = @_;
    # note $form no longer used
    
    my $err = sub {
        $$errref = "<?h1 <?_ml Error _ml?> h1?><?p $_[0] p?>";
        return 0;
    };

    unless (LJ::can_view($remote, $item)) {
        return $err->(BML::ml('talk.error.mustlogin'))
            unless defined $remote;
        return $err->(BML::ml('talk.error.notauthorised'));
    }

    return 1;
}

sub can_delete {
    my ($remote, $u, $up, $userpost) = @_; # remote, journal, posting user, commenting user
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $userpost ||
                $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq (ref $up ? $up->{'user'} : $up) ||
                LJ::check_rel($u, $remote, 'A');
    return 0;
}

sub can_screen {
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

    my $updated = LJ::talk2_do($dbcm, $userid, "L", $itemid, undef,
                               "UPDATE talk2 SET state='S' ".
                               "WHERE journalid=$userid AND jtalkid IN ($in) ".
                               "AND nodetype='L' AND nodeid=$itemid ".
                               "AND state NOT IN ('S','D')");
    if ($updated > 0) {
        LJ::replycount_do($u, $itemid, "decr", $updated);
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

    my $updated = LJ::talk2_do($dbcm, $userid, "L", $itemid, undef,
                               "UPDATE talk2 SET state='A' ".
                               "WHERE journalid=$userid AND jtalkid IN ($in) ".
                               "AND nodetype='L' AND nodeid=$itemid ".
                               "AND state='S'");
    if ($updated > 0) {
        LJ::replycount_do($u, $itemid, "incr", $updated);
        my $hasscreened = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 " .
                                                 "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='S'");
        LJ::set_logprop($u, $itemid, { 'hasscreened' => 0 }) unless $hasscreened;
    }

    LJ::Talk::update_commentalter($u, $itemid);
    return;
}

# retrieves data from the talk2 table (but preferrably memcache)
# returns a hashref (key -> { 'talkid', 'posterid', 'datepost', 
#                             'parenttalkid', 'state' } , or undef on failure
sub get_talk_data
{
    my ($u, $nodetype, $nodeid) = @_;
    return undef unless $u && $u->{'userid'};
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;

    my $ret = {};

    # check for data in memcache
    my $DATAVER = "1";  # single character
    my $memkey = [$u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid"];
    my $lockkey = $memkey->[1];
    my $packed = LJ::MemCache::get($memkey);

    # we check the replycount in memcache, the value we count, and then fix it up
    # if it seems necessary.
    my $rp_memkey = $nodetype eq "L" ? [$u->{'userid'}, "rp:$u->{'userid'}:$nodeid"] : undef;
    my $rp_count = $rp_memkey ? LJ::MemCache::get($rp_memkey) : 0;
    my $rp_ourcount = 0;
    my $fixup_rp = sub {
        return unless $nodetype eq "L";
        return if $rp_count == $rp_ourcount;
        return unless @LJ::MEMCACHE_SERVERS;

        # probably need to fix.  checking is at least warranted.
        my $dbcm = LJ::get_cluster_master($u);
        return unless $dbcm;
        $dbcm->do("LOCK TABLES log2 WRITE, talk2 READ");
        my $ct = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 WHERE ".
                                        "journalid=? AND nodetype='L' AND nodeid=? ".
                                        "AND state='A'", undef, $u->{'userid'},
                                        $nodeid);
        $dbcm->do("UPDATE log2 SET replycount=? WHERE journalid=? AND jitemid=?",
                  undef, int($ct), $u->{'userid'}, $nodeid);
        print STDERR "Fixing replycount for $u->{'userid'}/$nodeid from $rp_count to $ct\n"
            if $LJ::DEBUG{'replycount_fix'};
        $dbcm->do("UNLOCK TABLES");
        LJ::MemCache::delete($rp_memkey);
    };

    my $memcache_good = sub {
        return $packed && substr($packed,0,1) eq $DATAVER &&
            length($packed) % 16 == 1;
    };

    my $memcache_decode = sub {
        my $n = (length($packed) - 1) / 16;
        for (my $i=0; $i<$n; $i++) {
            my ($f1, $par, $poster, $time) = unpack("NNNN",substr($packed,$i*16+1,16));
            my $state = chr($f1 & 255);
            my $talkid = $f1 >> 8;
            $ret->{$talkid} = {
                talkid => $talkid,
                state => $state,
                posterid => $poster,
                datepost => LJ::mysql_time($time),
                parenttalkid => $par,
            };
            $rp_ourcount++ if $state eq "A";
        }
        $fixup_rp->();
        return $ret;
    };
    
    return $memcache_decode->() if $memcache_good->();

    my $dbcm = LJ::get_cluster_master($u);
    return undef unless $dbcm;

    my $lock = $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    return undef unless $lock;

    # it's quite likely (for a popular post) that the memcache was 
    # already populated while we were waiting for the lock
    $packed = LJ::MemCache::get($memkey);
    if ($memcache_good->()) {
        $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);
        $memcache_decode->();
        return $ret;
    }

    my $memval = $DATAVER;
    my $sth = $dbcm->prepare("SELECT t.jtalkid AS 'talkid', t.posterid, ".
                             "t.datepost, t.parenttalkid, t.state ".
                             "FROM talk2 t ".
                             "WHERE t.journalid=? AND t.nodetype=? AND t.nodeid=?");
    $sth->execute($u->{'userid'}, $nodetype, $nodeid);
    die $dbcm->errstr if $dbcm->err;
    while (my $r = $sth->fetchrow_hashref) {
        $ret->{$r->{'talkid'}} = $r;
        $memval .= pack("NNNN", 
                        ($r->{'talkid'} << 8) + ord($r->{'state'}),
                        $r->{'parenttalkid'},
                        $r->{'posterid'},
                        LJ::mysqldate_to_time($r->{'datepost'}));
        $rp_ourcount++ if $r->{'state'} eq "A";
    }
    LJ::MemCache::set($memkey, $memval);
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    $fixup_rp->();

    return $ret;
    
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
#      - subject
#      - body
#      - props => { propname => value, ... }
#      - children => [ hashrefs like these ]
#      - _loaded => 1 (if fully loaded, subject & body)
#        unknown items will never be _loaded
#      - _show => {0|1}, if item is to be ideally shown (0 if deleted or screened)
sub load_comments
{
    my ($u, $remote, $nodetype, $nodeid, $opts) = @_;

    my $n = $u->{'clusterid'};

    my $posts = get_talk_data($u, $nodetype, $nodeid);  # hashref, talkid -> talk2 row, or undef
    unless ($posts) {
        $opts->{'out_error'} = "nodb";
        return;
    }
    my %users_to_load;  # userid -> 1
    my @posts_to_load;  # talkid scalars
    my %children;       # talkid -> [ childenids+ ]

    my $uposterid = $opts->{'up'} ? $opts->{'up'}->{'userid'} : 0;

    my $post_count = 0;
    {
        my %showable_children;  # $id -> $count

        foreach my $post (sort { $b->{'talkid'} <=> $a->{'talkid'} } values %$posts) {
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
                if $post->{'parenttalkid'} && ! $posts->{$post->{'parenttalkid'}};

            $post->{'children'} = [ map { $posts->{$_} } @{$children{$post->{'talkid'}} || []} ];

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
    $thread = 0 unless $posts->{$thread};

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
        while ($posts->{$viewid} && $posts->{$viewid}->{'parenttalkid'}) {
            $viewid = $posts->{$viewid}->{'parenttalkid'};
        }
        for (my $ti = 0; $ti < @top_replies; ++$ti) {
            if ($posts->{$top_replies[$ti]}->{'talkid'} == $viewid) {
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
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'_loaded'} = 1;
        $posts->{$talkid}->{'subject'} = $posts_loaded->{$talkid}->[0];
        $posts->{$talkid}->{'body'} = $posts_loaded->{$talkid}->[1];
        $users_to_load{$posts->{$talkid}->{'posterid'}} = 1;
    }
    foreach my $talkid (@subjects_to_load) {
        next unless $posts->{$talkid}->{'_show'};
        $posts->{$talkid}->{'subject'} = $subjects_loaded->{$talkid}->[0];
        $users_to_load{$posts->{$talkid}->{'posterid'}} ||= 0.5;  # only care about username
    }

    # load meta-data
    {
        my %props;
        LJ::load_talk_props2($u->{'userid'}, \@posts_to_load, \%props);
        foreach (keys %props) {
            next unless $posts->{$_}->{'_show'};
            $posts->{$_}->{'props'} = $props{$_};
        }
    }

    if ($LJ::UNICODE) {
        foreach (@posts_to_load) {
            if ($posts->{$_}->{'props'}->{'unknown8bit'}) {
                LJ::item_toutf8($u, \$posts->{$_}->{'subject'},
                                \$posts->{$_}->{'body'},
                                {});
              }
        }
    }

    # load users who posted
    delete $users_to_load{0};
    my %up = ();
    if (%users_to_load) {
        LJ::load_userids_multiple([ map { $_, \$up{$_} } keys %users_to_load ]);
          
        # fill in the 'userpost' member on each post being shown
        while (my ($id, $post) = each %$posts) {
            $post->{'userpost'} = $up{$post->{'posterid'}}->{'user'} if
                $up{$post->{'posterid'}};
        }
    }

    # optionally give them back user refs
    if (ref($opts->{'userref'}) eq "HASH") {
        my %userpics = ();
        
        # copy into their ref the users we've already loaded above.
        while (my ($k, $v) = each %up) {
            $opts->{'userref'}->{$k} = $v;
        }

        # optionally load userpics
        if (ref($opts->{'userpicref'}) eq "HASH") {
            my %load_pic;
            foreach my $talkid (@posts_to_load) {
                my $post = $posts->{$talkid};
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
    
    return map { $posts->{$_} } @top_replies;
}

sub talkform {
    # replyto : init->replyto
    # curpickw : FORM{prop_picture_keyword} or something like that
    my ($remote, $journalu, $parpost, $replyto, $ditemid, $curpickw) = @_;

    my $ret;
    my $pics = LJ::Talk::get_subjecticons();

    # once we clean out talkpost.bml, this will need to be changed.
    BML::set_language_scope('/talkpost.bml');

    if ($parpost->{'state'} eq "S") {
        $ret .= "<div class='ljwarnscreened'>$BML::ML{'.warnscreened'}</div>";
    }
    $ret .= "<form method='post' action='$LJ::SITEROOT/talkpost_do.bml' id='postform'>";

    # hidden values
    my $parent = $replyto+0;
    $ret .= LJ::html_hidden("parenttalkid", $parent,
                            "itemid", $ditemid,
                            "journal", $journalu->{'user'});

    # challenge
    {
        my ($time, $secret) = LJ::get_secret();
        my $rchars = LJ::rand_chars(20);
        my $chal = "$ditemid-$journalu->{userid}-$time-$rchars";
        my $res = Digest::MD5::md5_hex($secret . $chal);
        $ret .= LJ::html_hidden("chrp1", "$chal-$res");
    }

    # from registered user or anonymous?
    $ret .= "<table>\n";
    if ($journalu->{'opt_whocanreply'} eq "all") {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$BML::ML{'.opt.from'}</td>";
        $ret .= "<td align='middle'><input type='radio' name='usertype' value='anonymous' id='talkpostfromanon'></td>";
        $ret .= "<td align='left'><b><label for='talkpostfromanon'>$BML::ML{'.opt.anonymous'}</label></b>";
        if ($journalu->{'opt_whoscreened'} eq 'A' ||
            $journalu->{'opt_whoscreened'} eq 'R' ||
            $journalu->{'opt_whoscreened'} eq 'F') {
            $ret .= " " . $BML::ML{'.opt.willscreen'};
        }
        $ret .= "</td></tr>\n";
    } elsif ($journalu->{'opt_whocanreply'} eq "reg") {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$BML::ML{'.opt.from'}</td><td align='middle'>(  )</td>";
        $ret .= "<td align='left' colspan='3'><font color='#c0c0c0'><b>$BML::ML{'.opt.anonymous'}</b></font>$BML::ML{'.opt.noanonpost'}</td>";
        $ret .= "</tr>\n";
    } else {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>$BML::ML{'.opt.from'}</td>";
        $ret .= "<td align='middle'>(  )</td>";
        $ret .= "<td align='left' colspan='3'><font color='#c0c0c0'><b>$BML::ML{'.opt.anonymous'}</b></font>" .
            BML::ml(".opt.friendsonly", {'username'=>"<b>$journalu->{'user'}</b>"}) 
            . "</td>";
        $ret .= "</tr>\n";
    }

    my $checked = "checked='checked'";
    if ($remote) {
        $ret .= "<tr valign='middle'>";
        $ret .= "<td align='right'>&nbsp;</td>";
        if (LJ::is_banned($remote, $journalu)) {
            $ret .= "<td align='middle'>( )</td>";
            $ret .= "<td align='left'><span class='ljdeem'>" . BML::ml(".opt.loggedin", {'username'=>"<i>$remote->{'user'}</i>"}) . "</font>" . BML::ml(".opt.bannedfrom", {'journal'=>$journalu->{'user'}}) . "</td>";
        } else {
            $ret .= "<td align='middle'><input type='radio' name='usertype' value='cookieuser' id='talkpostfromremote' $checked /></td>";
            $ret .= "<td align='left'><label for='talkpostfromremote'>" . BML::ml(".opt.loggedin", {'username'=>"<i>$remote->{'user'}</i>"}) . "</label>\n";
            $ret .= "<input type='hidden' name='cookieuser' value='$remote->{'user'}' id='cookieuser' />\n";
            if ($journalu->{'opt_whoscreened'} eq 'A' ||
                ($journalu->{'opt_whoscreened'} eq 'F' &&
                 !LJ::is_friend($journalu, $remote))) {
                $ret .= " " . $BML::ML{'.opt.willscreen'};
            }
            $ret .= "</td>";
            $checked = "";
        }
        $ret .= "</tr>\n";
    }

    # ( ) LiveJournal user:
    $ret .= "<tr valign='middle'>";
    $ret .= "<td>&nbsp;</td>";
    $ret .= "<td align=middle><input type='radio' name='usertype' value='user' id='talkpostfromlj' $checked />";
    $ret .= "</td><td align='left'><b><label for='talkpostfromlj'>$BML::ML{'.opt.ljuser'}</label></b> ";
    $ret .= $BML::ML{'.opt.willscreenfriend'} if $journalu->{'opt_whoscreened'} eq 'F';
    $ret .= $BML::ML{'.opt.willscreen'} if $journalu->{'opt_whoscreened'} eq 'A';
    $ret .= "</td></tr>\n";

    # Username: [    ] Password: [    ]  Login? [ ]
    $ret .= "<tr valign='middle' align='left'><td colspan='2'></td><td>";
    $ret .= "$BML::ML{'Username'}:&nbsp;<input class='textbox' name='userpost' size='13' maxlength='15' id='username' /> ";
    $ret .= "$BML::ML{'Password'}:&nbsp;<input class='textbox' name='password' type='password' maxlength='30' size='13' id='password' /> <label for='logincheck'>$BML::ML{'.loginq'}&nbsp;</label><input type='checkbox' name='do_login' id='logincheck' /></td></tr>\n";
    
    my $basesubject = "";
    if ($replyto) {
        $basesubject = $parpost->{'subject'};
        $basesubject =~ s/^Re:\s*//i;
        if ($basesubject) {
            $basesubject = "Re: $basesubject";
            $basesubject = BML::eall($basesubject);
        }
    }

    # subject
    $ret .= "<tr valign='top'><td align='right'>$BML::ML{'.opt.subject'}</td><td colspan='4'><input class='textbox' type='text' size='50' maxlength='100' name='subject' value=\"$basesubject\" />\n";

    # Subject Icon toggle button
    {
        $ret .= "<input type='hidden' id='subjectIconField' name='subjecticon' value='none'>\n";
        $ret .= "<script type='text/javascript' language='Javascript'>\n";
        $ret .= "<!--\n";
        $ret .= "if (document.getElementById) {\n";
        $ret .= "document.write(\"";
        $ret .= LJ::ejs(LJ::Talk::show_none_image("id='subjectIconImage' style='cursor:hand' align='absmiddle' ".
                                                  "onclick='subjectIconListToggle();' ".
                                                  "title='Click to change the subject icon'"));
        $ret .="\");\n";


        # spit out a pretty table of all the possible subjecticons
        $ret .= "document.write(\"";
        $ret .= "<blockquote style='display:none;' id='subjectIconList'>";
        $ret .= "<table border='0' cellspacing='5' cellpadding='0' style='border: 1px solid #AAAAAA'>\");\n";

        foreach my $type (@{$pics->{'types'}}) {
            
            $ret .= "document.write(\"<tr>\");\n";

            # make an option if they don't want an image
            if ($type eq $pics->{'types'}->[0]) { 
                $ret .= "document.write(\"";
                $ret .= "<td valign='middle' align='middle'>";
                $ret .= LJ::Talk::show_none_image(
                        "id='none' onclick='subjectIconChange(this);' style='cursor:hand' title='No subject icon'");
                $ret .= "</td>\");\n";
            }

            # go through and make clickable image rows.
            foreach (@{$pics->{'lists'}->{$type}}) {
                $ret .= "document.write(\"";
                $ret .= "<td valign='middle' align='middle'>";
                $ret .= LJ::Talk::show_image($pics, $_->{'id'}, 
                        "id='$_->{'id'}' onclick='subjectIconChange(this);' style='cursor:hand'");
                $ret .= "</td>\");\n";
            }
            
            $ret .= "document.write(\"</tr>\");\n";
            
        }
        # end that table, bar!
        $ret .= "document.write(\"</table></blockquote>\");\n";

        $ret .= "}\n";
        $ret .="//-->\n";
        $ret .= "</script>\n";
    }

    # finish off subject line
    $ret .= "<div id='ljnohtmlsubj' class='ljdeem'>$BML::ML{'.nosubjecthtml'}</div></td></tr>\n";

    $ret .= "<tr><td align='right'>&nbsp;</td><td colspan='4'>";
    $ret .= "$BML::ML{'.opt.noautoformat'}<input type='checkbox' value='1' name='prop_opt_preformatted' />";
    $ret .= LJ::help_icon("noautoformat", " ");
    
    my %res;
    if ($remote) {
        LJ::do_request({ "mode" => "login",
                         "ver" => ($LJ::UNICODE ? "1" : "0"),
                         "user" => $remote->{'user'},
                         "getpickws" => 1,
                       }, \%res, { "noauth" => 1, "userid" => $remote->{'userid'} });
    }
    if ($res{'pickw_count'}) {
        $ret .= BML::ml('.label.picturetouse',{'username'=>$remote->{'user'}});
        my @pics;
        for (my $i=1; $i<=$res{'pickw_count'}; $i++) {
            push @pics, $res{"pickw_$i"};
        }
        @pics = sort { lc($a) cmp lc($b) } @pics;
        $ret .= LJ::html_select({'name' => 'prop_picture_keyword', 
                                 'selected' => $curpickw, },
                                ("", $BML::ML{'.opt.defpic'}, map { ($_, $_) } @pics));
        $ret .= LJ::help_icon("userpics", " ");
    }
    $ret .= "</td></tr>\n";

    # textarea for their message body
    $ret .= "<tr valign='top'><td align='right'>$BML::ML{'.opt.message'}</td><td colspan='4' style='width: 90%'>";
    $ret .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' id='commenttext' style='width: 100%'></textarea>";
    $ret .= "<br /><input type='submit' name='submitpost' value='$BML::ML{'.opt.submit'}' />\n";

    ## preview stuff
    $ret .= "<input type='submit' name='submitpreview' value='$BML::ML{'talk.btn.preview'}' />\n";
    if ($LJ::SPELLER) {
        $ret .= "<input type='checkbox' name='do_spellcheck' value='1' id='spellcheck' /> <label for='spellcheck'>$BML::ML{'talk.spellcheck'}</label>";
    }

    if ($journalu->{'opt_logcommentips'} eq "A") {
        $ret .= "<br />$BML::ML{'.logyourip'}";
        $ret .= LJ::help_icon("iplogging", " ");
    }
    if ($journalu->{'opt_logcommentips'} eq "S") {
        $ret .= "<br />$BML::ML{'.loganonip'}";
        $ret .= LJ::help_icon("iplogging", " ");
    }

    $ret .= "</td></tr></table>\n";

    # Some JavaScript to help the UI out

    $ret .= "<script type='text/javascript' language='JavaScript'>\n";
    $ret .= "var usermismatchtext = \"" . LJ::ejs($BML::ML{'.usermismatch'}) . "\";\n";
    $ret .= "</script><script type='text/javascript' language='JavaScript' src='/js/talkpost.js'></script>";
    $ret .= "</form>\n";

    return $ret;
}

package LJ::Talk::Post;

sub format_text_mail {
    my ($targetu, $parent, $comment, $talkurl, $item) = @_;
    my $dtalkid = $comment->{talkid}*256 + $item->{anum};

    $Text::Wrap::columns = 76;

    my $who = "Somebody";
    if ($comment->{u}{user}) {
        $who = "$comment->{u}{name} ($comment->{u}{user})";
    }

    my $text = "";
    if ($targetu == $item->{entryu}) {
        if ($parent->{ispost}) {
            $text .= "$who replied to your $LJ::SITENAMESHORT post in which you said:";
        } else {
            $text .= "$who replied to another comment somebody left in your $LJ::SITENAMESHORT post.  ";
            $text .= "The comment they replied to was:";
        }
    } else {
        $text .= "$who replied to your $LJ::SITENAMESHORT comment in which you said:";
    }
    $text .= "\n\n";
    $text .= indent($parent->{body}, ">") . "\n\n";
    $text .= "Their reply was:\n\n";
    if ($comment->{subject}) {
        $text .= Text::Wrap::wrap("  Subject: ",
                                  "           ",
                                  $comment->{subject}) . "\n\n";
    }
    $text .= indent($comment->{body});
    $text .= "\n\n";

    if ($comment->{state} eq 'S') {
        $text .= "This comment was screened.  You must respond to it ".
                 "or unscreen it before others can see it.\n\n";
    }

    my $opts = "";
    $opts .= "Options:\n\n";
    $opts .= "  - View the discussion:\n";
    $opts .= "    " . LJ::Talk::talkargs($talkurl, "thread=$dtalkid") . "\n";
    $opts .= "  - View all comments on the entry:\n";
    $opts .= "    $talkurl\n";
    $opts .= "  - Reply to the comment:\n";
    $opts .= "    " . LJ::Talk::talkargs($talkurl, "replyto=$dtalkid") . "\n";
    if ($comment->{state} eq 'S') {
        $opts .= "  - Unscreen the comment:\n";
        $opts .= "    $LJ::SITEROOT/talkscreen.bml?mode=unscreen&journal=$item->{journalu}{user}&talkid=$dtalkid\n";
    }
    if (LJ::Talk::can_delete($targetu, $item->{journalu}, $item->{entryu}, $comment->{u})) {
        $opts .= "  - Delete the comment:\n";
        $opts .= "    $LJ::SITEROOT/delcomment.bml?journal=$item->{journalu}{user}&id=$dtalkid\n";
    }
    
    my $footer = "";
    $footer .= "-- $LJ::SITENAME\n\n";
    $footer .= "(If you'd prefer to not get these updates, go to $LJ::SITEROOT/editinfo.bml and turn off the relevant options.)";
    return Text::Wrap::wrap("", "", $text) . "\n" . $opts . "\n" . Text::Wrap::wrap("", "", $footer);
}

sub format_html_mail {
    my ($targetu, $parent, $comment, $encoding, $talkurl, $item) = @_;
    my $ditemid =    $item->{itemid}*256 + $item->{anum};
    my $dtalkid = $comment->{talkid}*256 + $item->{anum};
    my $threadurl = LJ::Talk::talkargs($talkurl, "thread=$dtalkid");

    my $who = "Somebody";
    if ($comment->{u}{name}) {
        $who = "$comment->{u}{name} ".
            "(<a href=\"$LJ::SITEROOT/userinfo.bml?user=$comment->{u}{user}\">$comment->{u}{user}</a>)";
    }

    my $html = "";
    $html .= "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=$encoding\" /></head>\n<body>\n";

    my $intro;
    my $cleanbody = $parent->{body};
    if ($targetu == $item->{entryu}) {
        if ($parent->{ispost}) {
            $intro = "$who replied to <a href=\"$talkurl\">your $LJ::SITENAMESHORT post</a> in which you said:";
            LJ::CleanHTML::clean_event(\$cleanbody, {preformatted => $parent->{preformat}});
        } else {
            $intro = "$who replied to another comment somebody left in ";
            $intro .= "<a href=\"$talkurl\">your $LJ::SITENAMESHORT post</a>.  ";
            $intro .= "The comment they replied to was:";
            LJ::CleanHTML::clean_comment(\$cleanbody, $parent->{preformat});
        }
    } else {
        $intro = "$who replied to <a href=\"$talkurl\">your $LJ::SITENAMESHORT comment</a> ";
        $intro .= "in which you said:";
        LJ::CleanHTML::clean_comment(\$cleanbody, $parent->{preformat});
    }

    my $pichtml;
    if ($comment->{u}{defaultpicid} || $comment->{pic}) {
        my $picid = $comment->{pic} ? $comment->{pic}{'picid'} : $comment->{u}{'defaultpicid'};
        unless ($comment->{pic}) {
            my %pics;
            LJ::load_userpics(\%pics, [ $comment->{u}{'defaultpicid'} ]);
            $comment->{pic} = $pics{$picid};
        }
        if ($comment->{pic}) {
            $pichtml = "<img src=\"$LJ::USERPIC_ROOT/$picid/$comment->{pic}{'userid'}\" align='absmiddle' ".
                "width='$comment->{pic}{'width'}' height='$comment->{pic}{'height'}' ".
                "hspace='1' vspace='2' alt='' /> ";
        }
    }

    if ($pichtml) {
        $html .= "<table><tr valign='top'><td>$pichtml</td><td width='100%'>$intro</td></tr></table>\n";
    } else {
        $html .= "<table><tr valign='top'><td width='100%'>$intro</td></tr></table>\n";
    }
    $html .= blockquote($cleanbody);

    $html .= "\n\nTheir reply was:\n\n";
    $cleanbody = $comment->{body};
    LJ::CleanHTML::clean_comment(\$cleanbody, $comment->{preformat});
    my $pics = LJ::Talk::get_subjecticons();
    my $icon = LJ::Talk::show_image($pics, $comment->{subjecticon}); 

    my $heading;
    if ($comment->{subject}) {
        $heading = "<b>Subject:</b> " . LJ::ehtml($comment->{subject});
    }
    $heading .= $icon;
    $heading .= "<br />" if $heading;
    # this needs to be one string so blockquote handles it properly.
    $html .= blockquote("$heading$cleanbody");

    if ($comment->{state} eq 'S') {
        $html .= "<p>This comment was screened.  You must respond to it or unscreen it before others can see it.</p>\n";
    }

    $html .= "<p>From here, you can:\n";
    $html .= "<ul><li><a href=\"$threadurl\">View the thread</a> starting from this comment</li>\n";
    $html .= "<li><a href=\"$talkurl\">View all comments</a> to this entry</li>\n";
    $html .= "<li><a href=\"" . LJ::Talk::talkargs($talkurl, "replyto=$dtalkid") . "\">Reply</a> at the webpage</li>\n";
    if ($comment->{state} eq 'S') {
        $html .= "<li><a href=\"$LJ::SITEROOT/talkscreen.bml?mode=unscreen&journal=$item->{journalu}{user}&talkid=$dtalkid\">Unscreen the comment</a></li>";
    }
    if (LJ::Talk::can_delete($targetu, $item->{journalu}, $item->{entryu}, $comment->{u})) {
        $html .= "<li><a href=\"$LJ::SITEROOT/delcomment.bml?journal=$item->{journalu}{user}&id=$dtalkid\">Delete the comment</a></li>";
    }
    $html .= "</ul></p>";

    my $want_form = 1;  # this should probably be a preference, or maybe just always off.
    if ($want_form) {
        $html .= "If your mail client supports it, you can also reply here:\n";
        $html .= "<blockquote><form method='post' target='ljreply' action=\"$LJ::SITEROOT/talkpost_do.bml\">\n";

        $html .= LJ::html_hidden(
            usertype     =>  "user",
            parenttalkid =>  $comment->{talkid},
            itemid       =>  $ditemid,
            journal      =>  $item->{journalu}{user},
            userpost     =>  $targetu->{user},
            ecphash      =>  LJ::Talk::ecphash($item->{itemid}, $comment->{talkid}, $targetu->{password})
        );

        $html .= "<input type='hidden' name='encoding' value='$encoding' />" unless $encoding eq "UTF-8";
        my $newsub = $comment->{subject};
        unless (!$newsub || $newsub =~ /^Re:/) { $newsub = "Re: $newsub"; }
        $html .= "<b>Subject: </b> <input name='subject' size='40' value=\"" . LJ::ehtml($newsub) . "\" />";
        $html .= "<p><b>Message</b><br /><textarea rows='10' cols='50' wrap='soft' name='body'></textarea>";
        $html .= "<br /><input type='submit' value=\"Post Reply\">";
        $html .= "</form></blockquote>\n";
    }
    $html .= "<p><font size='-1'>(If you'd prefer to not get these updates, go to <a href=\"$LJ::SITEROOT/editinfo.bml\">your user profile page</a> and turn off the relevant options.)</font></p>\n";
    $html .= "</body>\n";

    return $html;
}

sub indent {
    my $a = shift;
    my $leadchar = shift || " ";
    $Text::Wrap::columns = 76;
    return Text::Wrap::fill("$leadchar ", "$leadchar ", $a);
}

sub blockquote {
    my $a = shift;
    return "<blockquote style='border-left: #000040 2px solid; margin-left: 0px; margin-right: 0px; padding-left: 15px; padding-right: 0px'>$a</blockquote>";
}
 
# entryu     : user who posted the entry this comment is under.
# journalu   : journal this entry is in.
# parent     : comment/entry this post is in response to.
# comment    : the comment itself.
# item       : entry this comment falls under.
sub mail_comments {
    my ($entryu, $journalu, $parent, $comment, $item) = @_;
    my $itemid = $item->{itemid};
    my $ditemid = $itemid*256 + $item->{anum};
    my $dtalkid = $comment->{talkid}*256 + $item->{anum};
    my $talkurl = LJ::journal_base($journalu) . "/$ditemid.html";
    my $threadurl = LJ::Talk::talkargs($talkurl, "thread=$dtalkid");

    # check to see if parent post is from a registered livejournal user, and 
    # mail them the response
    my $parentcomment = "";
    my $parentmailed = "";  # who if anybody was just mailed

    # if a response to another comment, send a mail to the parent commenter.
    if ($parent->{talkid}) {  
        my $dbcm = LJ::get_cluster_master($journalu);
        # FIXME: remove this query:
        my $sth = $dbcm->prepare("SELECT t.posterid, tt.body FROM talk2 t, talktext2 tt ".
                                 "WHERE t.journalid=? AND tt.journalid=? ".
                                 "AND   t.jtalkid=?   AND tt.jtalkid=?");
        $sth->execute($journalu->{userid}, $journalu->{userid}, $parent->{talkid}, $parent->{talkid});
        my ($paruserid, $parbody) = $sth->fetchrow_array;
        LJ::text_uncompress(\$parbody);
        $parentcomment = $parbody;

        my %props = ($parent->{talkid} => {});
        LJ::load_talk_props2($dbcm, $journalu->{'userid'}, [$parent->{talkid}], \%props);
        $parent->{preformat} = $props{$parent->{talkid}}->{'opt_preformatted'};

        # convert to UTF-8 if necessary
        my $parentsubject = $parent->{subject};
        if ($LJ::UNICODE && $props{$parent->{talkid}}->{'unknown8bit'}) {
            LJ::item_toutf8($journalu, \$parentsubject, \$parentcomment, {});
        }
        
        if ($paruserid) {
            my $paru = LJ::load_userid($paruserid);
            LJ::load_user_props($paru, 'mailencoding');
            LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
                unless %LJ::CACHE_ENCODINGS;
            
            if ($paru->{'opt_gettalkemail'} eq "Y" &&
                $paru->{'email'} ne $comment->{u}{'email'} &&
                $paru->{'status'} eq "A")
            {
                $parentmailed = $paru->{'email'};
                my $encoding = $paru->{'mailencoding'} ? $LJ::CACHE_ENCODINGS{$paru->{'mailencoding'}} : "UTF-8";
                my $part;

                my $headersubject = $comment->{subject};
                if ($LJ::UNICODE && $encoding ne "UTF-8") {
                    $headersubject = Unicode::MapUTF8::from_utf8({-string=>$headersubject, -charset=>$encoding}); 
                }

                if (!LJ::is_ascii($headersubject)) {
                    $headersubject = MIME::Words::encode_mimeword($headersubject, 'B', $encoding);
                }

                my $fromname = $comment->{u}{'user'} ? "$comment->{u}{'user'} - $LJ::SITENAMEABBREV Comment" : "$LJ::SITENAMESHORT Comment";
                my $msg =  new MIME::Lite ('From' => "$LJ::BOGUS_EMAIL ($fromname)",
                                           'To' => $paru->{'email'},
                                           'Subject' => ($headersubject || "Reply to your comment..."),
                                           'Type' => 'multipart/alternative');
                
                $parent->{u} = $paru;
                $parent->{body} = $parentcomment;
                $parent->{ispost} = 0;
                $item->{entryu} = $entryu;
                $item->{journalu} = $journalu;
                my $text = format_text_mail($paru, $parent, $comment, $talkurl, $item);
 
                if ($LJ::UNICODE && $encoding ne "UTF-8") {
                    $text = Unicode::MapUTF8::from_utf8({-string=>$text, -charset=>$encoding}); 
                }
                $part = $msg->attach('Type' => 'TEXT',
                                     'Data' => $text,
                                     'Encoding' => 'quoted-printable',
                                     );
                $part->attr("content-type.charset" => $encoding)
                    if $LJ::UNICODE;

                if ($paru->{'opt_htmlemail'} eq "Y") {
                    my $html = format_html_mail($paru, $parent, $comment, $encoding, $talkurl, $item);
                    if ($LJ::UNICODE && $encoding ne "UTF-8") {
                        $html = Unicode::MapUTF8::from_utf8({-string=>$html, -charset=>$encoding}); 
                    }
                    $part = $msg->attach('Type' => 'text/html',
                                         'Data' => $html,
                                         'Encoding' => 'quoted-printable',
                                         );
                    $part->attr("content-type.charset" => $encoding)
                        if $LJ::UNICODE;
                }

                LJ::send_mail($msg);
            }
        }
    }

    # send mail to the poster of the entry
    if ($entryu->{'opt_gettalkemail'} eq "Y" &&
        !$item->{props}->{'opt_noemail'} &&
        $comment->{u}{user} ne $entryu->{'user'} &&
        $entryu->{'email'} ne $parentmailed &&
        $entryu->{'status'} eq "A") 
    {
        LJ::load_user_props($entryu, 'mailencoding');
        LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
            unless %LJ::CACHE_ENCODINGS;
        my $encoding = $entryu->{'mailencoding'} ? $LJ::CACHE_ENCODINGS{$entryu->{'mailencoding'}} : "UTF-8";
        my $part;

        my $headersubject = $comment->{subject};
        if ($LJ::UNICODE && $encoding ne "UTF-8") {
            $headersubject = Unicode::MapUTF8::from_utf8({-string=>$headersubject, -charset=>$encoding}); 
        }

        if (!LJ::is_ascii($headersubject)) {
            $headersubject = MIME::Words::encode_mimeword($headersubject, 'B', $encoding);
        }

        my $fromname = $comment->{u}{'user'} ? "$comment->{u}{'user'} - $LJ::SITENAMEABBREV Comment" : "$LJ::SITENAMESHORT Comment";
        my $msg =  new MIME::Lite ('From' => "$LJ::BOGUS_EMAIL ($fromname)",
                                   'To' => $entryu->{'email'},
                                   'Subject' => ($headersubject || "Reply to your post..."),
                                   'Type' => 'multipart/alternative');

        my $quote = $parentcomment ? $parentcomment : $item->{'event'};

        # if this is a response to a comment inside our journal,
        # we don't know who made the parent comment
        # (and it's potentially anonymous).
        if ($parentcomment) {
            $parent->{u} = undef;
            $parent->{body} = $parentcomment;
            $parent->{ispost} = 0;
        } else {
            $parent->{u} = $entryu;
            $parent->{body} = $item->{'event'},
            $parent->{ispost} = 1; 
            $parent->{preformat} = $item->{'props'}->{'opt_preformatted'};
        }
        $item->{entryu} = $entryu;
        $item->{journalu} = $journalu;

        my $text = format_text_mail($entryu, $parent, $comment, $talkurl, $item);

        if ($LJ::UNICODE && $encoding ne "UTF-8") {
            $text = Unicode::MapUTF8::from_utf8({-string=>$text, -charset=>$encoding}); 
        }
        $part = $msg->attach('Type' => 'TEXT',
                             'Data' => $text,
                             'Encoding' => 'quoted-printable',
                             );
        $part->attr("content-type.charset" => $encoding)
            if $LJ::UNICODE;
        
        if ($entryu->{'opt_htmlemail'} eq "Y") {
            my $html = format_html_mail($entryu, $parent, $comment, $encoding, $talkurl, $item);
            if ($LJ::UNICODE && $encoding ne "UTF-8") {
                $html = Unicode::MapUTF8::from_utf8({-string=>$html, -charset=>$encoding}); 
            }
            $part = $msg->attach('Type' => 'text/html',
                                 'Data' => $html,
                                 'Encoding' => 'quoted-printable',
                                 );
            $part->attr("content-type.charset" => $encoding)
                if $LJ::UNICODE;
        }
        
        LJ::send_mail($msg);
    }
}

sub enter_comment {
    my ($journalu, $parent, $item, $comment, $errref) = @_;

    my $partid = $parent->{talkid};
    my $itemid = $item->{itemid};

    my $err = sub {
        $$errref = "<h2>$_[0]</h2> <p>$_[1]";
        return 0;
    };

    my $jtalkid = LJ::alloc_user_counter($journalu, "T");
    return $err->("Database Error", "Could not generate a talkid necessary to post this comment.")
        unless $jtalkid; 

    my $dbcm = LJ::get_cluster_master($journalu);

    # insert the comment
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;
    
    my $errstr;
    LJ::talk2_do($dbcm, $journalu->{userid}, "L", $itemid, \$errstr,
                 "INSERT INTO talk2 ".
                 "(journalid, jtalkid, nodetype, nodeid, parenttalkid, posterid, datepost, state) ".
                 "VALUES (?,?,'L',?,?,?,NOW(),?)",
                 $journalu->{userid}, $jtalkid, $itemid, $partid, $posterid, $comment->{state});
    if ($errstr) {
        return $err->("Database Error",
            "There was an error posting your comment to the database.  " .
            "Please report this.  The error is: <b>$errstr</b>");
    }

    LJ::MemCache::incr([$journalu->{'userid'}, "talk2ct:$journalu->{'userid'}"]);

    $comment->{talkid} = $jtalkid;
    
    # add to poster's talkleft table, or the xfer place
    if ($posterid) {
        my $table;
        my $db = LJ::get_cluster_master($comment->{u});

        if ($db) {
            # remote's cluster is writable
            $table = "talkleft";
        } else {
            # log to global cluster, another job will move it later.
            $db = LJ::get_db_writer();
            $table = "talkleft_xfp";
        }
        my $pub  = $item->{'security'} eq "public" ? 1 : 0;
        if ($db) {
            $db->do("INSERT INTO $table (userid, posttime, journalid, nodetype, ".
                    "nodeid, jtalkid, publicitem) VALUES (?, UNIX_TIMESTAMP(), ".
                    "?, 'L', ?, ?, ?)", undef,
                    $posterid, $journalu->{userid}, $itemid, $jtalkid, $pub);
            
            LJ::MemCache::incr([$posterid, "talkleftct:$posterid"]);
        } else {
            # both primary and backup talkleft hosts down.  can't do much now.
        }
    }

    $dbcm->do("INSERT INTO talktext2 (journalid, jtalkid, subject, body) ".
              "VALUES (?, ?, ?, ?)", undef,
              $journalu->{userid}, $jtalkid, $comment->{subject}, 
              LJ::text_compress($comment->{body}));
    die $dbcm->errstr if $dbcm->err;

    my $memkey = "$journalu->{'clusterid'}:$journalu->{'userid'}:$jtalkid";
    LJ::MemCache::set([$journalu->{'userid'},"talksubject:$memkey"], $comment->{subject});
    LJ::MemCache::set([$journalu->{'userid'},"talkbody:$memkey"], $comment->{body});

    # dudata
    my $bytes = length($comment->{subject}) + length($comment->{body});
    # we used to do a LJ::dudata_set(..) on 'T' here, but decided
    # we could defer that.  to find size of a journal, summing
    # bytes in dudata is too slow (too many seeks)

    my %talkprop;   # propname -> value
    # meta-data
    $talkprop{'unknown8bit'} = 1 if $comment->{unknown8bit};
    $talkprop{'subjecticon'} = $comment->{subjecticon};

    $talkprop{'picture_keyword'} = $comment->{picture_keyword};

    $talkprop{'opt_preformatted'} = $comment->{preformat} ? 1 : 0;
    if ($journalu->{'opt_logcommentips'} eq "A" || 
        ($journalu->{'opt_logcommentips'} eq "S" && $comment->{usertype} ne "user")) 
    {
        my $ip = BML::get_remote_ip();
        my $forwarded = BML::get_client_header('X-Forwarded-For');
        $ip = "$forwarded, via $ip" if $forwarded && $forwarded ne $ip;
        $talkprop{'poster_ip'} = $ip;
    }

    # remove blank/0 values (defaults)
    foreach (keys %talkprop) { delete $talkprop{$_} unless $talkprop{$_}; }

    # update the talkprops
    LJ::load_props("talk");
    if (%talkprop) {
        my $values;
        my $hash = {};
        foreach (keys %talkprop) {
            my $p = LJ::get_prop("talk", $_);
            next unless $p;
            $hash->{$_} = $talkprop{$_};
            my $tpropid = $p->{'tpropid'};
            my $qv = $dbcm->quote($talkprop{$_});
            $values .= "($journalu->{'userid'}, $jtalkid, $tpropid, $qv),";
        }
        if ($values) {
            chop $values;
            $dbcm->do("INSERT INTO talkprop2 (journalid, jtalkid, tpropid, value) ".
                      "VALUES $values");
            die $dbcm->errstr if $dbcm->err;
        }
        LJ::MemCache::set([$journalu->{'userid'}, "talkprop:$journalu->{'userid'}:$jtalkid"], $hash);
    }
    
    # update the "replycount" summary field of the log table
    if ($comment->{state} eq 'A') {
        LJ::replycount_do($journalu, $itemid, "incr");
    }

    # update the "hasscreened" property of the log item if needed
    if ($comment->{state} eq 'S') {
        LJ::set_logprop($journalu, $itemid, { 'hasscreened' => 1 });
    }
    
    # update the comment alter property
    LJ::Talk::update_commentalter($journalu, $itemid);   
    return $jtalkid;
}

# XXX these strings should be in talk, but moving them means we have
# to retranslate.  so for now we're just gonna put it off.
my $SC = '/talkpost_do.bml';

sub init {
    my ($form, $remote, $errret) = @_;
    my $sth;

    my $err = sub {
        my $error = shift;
        push @$errret, $error;
        return undef;
    };
    my $bmlerr = sub {
        return $err->($BML::ML{$_[0]});
    };

    my $init = LJ::Talk::init($form);
    return $err->($init->{error}) if $init->{error}; 

    my $journalu = $init->{'journalu'};
    return $bmlerr->('talk.error.nojournal') unless $journalu;
    return $err->($LJ::MSG_READONLY_USER) if LJ::get_cap($journalu, "readonly");

    my $r = Apache->request;
    $r->notes("journalid" => $journalu->{'userid'});

    my $dbcm = LJ::get_cluster_master($journalu);
    return $bmlerr->('error.nodb') unless $dbcm;

    my $itemid = $init->{'itemid'}+0;

    my $item = LJ::Talk::get_journal_item($journalu, $itemid);

    if ($init->{'oldurl'} && $item) {
        $init->{'anum'} = $item->{'anum'};
        $init->{'ditemid'} = $init->{'itemid'}*256 + $item->{'anum'};
    }

    unless ($item && $item->{'anum'} == $init->{'anum'}) {
        return $bmlerr->('talk.error.noentry');
    }

    my $iprops = $item->{'props'};
    my $ditemid = $init->{'ditemid'}+0;

    my $talkurl = LJ::journal_base($journalu) . "/$ditemid.html";
    $init->{talkurl} = $talkurl;

    ### load users
    LJ::load_userids_multiple([
                               $item->{'posterid'} => \$init->{entryu},
                               ], [ $journalu ]);
    LJ::load_user_props($journalu, "opt_logcommentips", "opt_whoscreened");

    if ($form->{'userpost'} && $form->{'usertype'} ne "user") {
        unless ($form->{'usertype'} eq "cookieuser" &&
                $form->{'userpost'} eq $form->{'cookieuser'}) {
            $bmlerr->("$SC.error.confused_identity");
        }
    }

    # anonymous/cookie users cannot authenticate with ecphash
    if ($form->{'ecphash'} && $form->{'usertype'} ne "user") {
        $bmlerr->("$SC.error.badusername");
        return undef;
    }

    my $cookie_auth;
    if ($form->{'usertype'} eq "cookieuser") {
        $bmlerr->("$SC.error.lostcookie")
            unless ($remote && $remote->{'user'} eq $form->{'cookieuser'});
        return undef if @$errret;
        
        $cookie_auth = 1;
        $form->{'userpost'} = $remote->{'user'};
        $form->{'usertype'} = "user";
    }
    # XXXevan hack:  remove me when we fix preview.
    $init->{cookie_auth} = $cookie_auth;

    # test accounts may only comment on other test accounts.
    if ((grep { $form->{'userpost'} eq $_ } @LJ::TESTACCTS) && 
        !(grep { $journalu->{'user'} eq $_ } @LJ::TESTACCTS))
    {
        $bmlerr->("$SC.error.testacct");
    }

    my $userpost = lc($form->{'userpost'});
    my $up;             # user posting
    my $exptype;        # set to long if ! after username
    my $ipfixed;        # set to remote  ip if < after username
    my $used_ecp;       # ecphash was validated and used

    if ($form->{'usertype'} eq "user") {
        if ($form->{'userpost'}) {

            # parse inline login opts
            if ($form->{'userpost'} =~ s/[!<]{1,2}$//) {
                $exptype = 'long' if index($&, "!") >= 0;
                $ipfixed = LJ::get_remote_ip() if index($&, "<") >= 0;
            }

            $up = LJ::load_user($form->{'userpost'});
            if ($up) {
                ### see if the user is banned from posting here
                if (LJ::is_banned($up, $journalu)) {
                    $bmlerr->("$SC.error.banned");
                }

                if ($up->{'journaltype'} ne "P") {
                    $bmlerr->("$SC.error.postshared");
                }

                # if we're already authenticated via cookie, then userpost was set
                # to the authenticated username, so we got into this block, but we
                # don't want to re-authenticate, so just skip this
                unless ($cookie_auth) {

                    # if ecphash present, authenticate on that
                    if ($form->{'ecphash'}) {

                        if ($form->{'ecphash'} eq
                            LJ::Talk::ecphash($itemid, $form->{'parenttalkid'}, $up->{'password'}))
                        {
                            $used_ecp = 1;
                        } else {
                            $bmlerr->("$SC.error.badpassword");
                        }

                    # otherwise authenticate on username/password
                    } elsif (! LJ::auth_okay($up, $form->{'password'}, $form->{'hpassword'}))
                    {
                        $bmlerr->("$SC.error.badpassword");
                    }
                }

                # if the user chooses to log in, do so
                if ($form->{'do_login'} && ! @$errret) {
                    $init->{didlogin} = LJ::make_login_session($up, $exptype, $ipfixed);
                }
            } else {
                $bmlerr->("$SC.error.badusername");
            }
        } else {
            $bmlerr->("$SC.error.nousername");
        }
    }

    # validate the challenge/response value (anti-spammer)
    unless ($used_ecp) {
        my $chrp_err;
        if (my $chrp = $form->{'chrp1'}) {
            my ($c_ditemid, $c_uid, $c_time, $c_chars, $c_res) = 
                split(/\-/, $chrp);
            my $chal = "$c_ditemid-$c_uid-$c_time-$c_chars";
            my $secret = LJ::get_secret($c_time);
            my $res = Digest::MD5::md5_hex($secret . $chal);
            if ($res ne $c_res) {
                $chrp_err = "invalid";
            } elsif ($c_time < time() - 2*60*60) {
                $chrp_err = "too_old";
            }
        } else {
            $chrp_err = "missing";
        }
        if ($chrp_err) {
            my $ip = LJ::get_remote_ip();
            if ($LJ::DEBUG_TALKSPAM) {
                my $ruser = $remote ? $remote->{user} : "[nonuser]";
                print STDERR "talkhash error: from $ruser \@ $ip - $chrp_err - $talkurl\n";
            }
            if ($LJ::REQUIRE_TALKHASH) {
                return $err->("Sorry, form expired.  Press back, copy text, reload form, paste into new form, and re-submit.") 
                    if $chrp_err eq "too_old";
                return $err->("Missing parameters");
            }
        }
    }

    # anti-spam rate limiting 
    return $err->("You've hit the \"probably a spambot\" rate limit.") 
        unless check_rate($remote);
    
    # check that user can even view this post, which is required
    # to reply to it
    ####  Check security before viewing this post
    unless (LJ::can_view($up, $item)) {
        $bmlerr->("$SC.error.mustlogin") unless (defined $up);
        $bmlerr->("$SC.error.noauth");
        return undef;
    }

    # If the reply is to a comment, check that it exists.
    # if it's screened, check that the user has permission to
    # reply and unscreen it

    my $parpost;
    my $partid = $form->{'parenttalkid'}+0;

    if ($partid) {
        $sth = $dbcm->prepare("SELECT posterid, state FROM talk2 ".
                              "WHERE journalid=? AND jtalkid=?");
        $sth->execute($journalu->{userid}, $partid);
        $parpost = $sth->fetchrow_hashref;

        unless ($parpost) {
            $bmlerr->("$SC.error.noparent");
        }

        # can't use $remote because we may get here
        # with a reply from email. so use $up instead of $remote
        # in the call below.

        if ($parpost && $parpost->{'state'} eq "S" && 
            !LJ::Talk::can_unscreen($up, $journalu, $init->{entryu}, $init->{entryu}{'user'})) {
            $bmlerr->("$SC.error.screened");
        }
    }
    $init->{parpost} = $parpost;

    # don't allow anonymous comments on syndicated items
    if ($journalu->{'journaltype'} eq "Y" && $journalu->{'opt_whocanreply'} eq "all") {
        $journalu->{'opt_whocanreply'} = "reg";
    }

    if ($form->{'usertype'} ne "user" && $journalu->{'opt_whocanreply'} ne "all") {
        $bmlerr->("$SC.error.noanon");
    }

    if ($iprops->{'opt_nocomments'}) {
        $bmlerr->("$SC.error.nocomments");
    }

    if ($up) {
        if ($up->{'status'} eq "N") {
            $bmlerr->("$SC.error.noverify");
        }
        if ($up->{'statusvis'} eq "D") {
            $bmlerr->("$SC.error.deleted");
        } elsif ($up->{'statusvis'} eq "S") {
            $bmlerr->("$SC.error.suspended");
        }
    }

    if ($journalu->{'opt_whocanreply'} eq "friends") {
        if ($up) {
            if ($up->{'userid'} != $journalu->{'userid'}) {
                unless (LJ::is_friend($journalu, $up)) {
                    $err->(BML::ml("$SC.error.notafriend", {'user'=>$journalu->{'user'}}));
                }
            }
        } else {
            $err->(BML::ml("$SC.error.friendsonly", {'user'=>$journalu->{'user'}}));
        }
    }

    unless ($form->{'body'} =~ /\S/) {
        $bmlerr->("$SC.error.blankmessage");
    }

    # in case this post comes directly from the user's mail client, it
    # may have an encoding field for us.
    if ($form->{'encoding'}) {
        $form->{'body'} = Unicode::MapUTF8::to_utf8({-string=>$form->{'body'}, -charset=>$form->{'encoding'}});
        $form->{'subject'} = Unicode::MapUTF8::to_utf8({-string=>$form->{'subject'}, -charset=>$form->{'encoding'}});
    }
    
    # unixify line-endings
    $form->{'body'} =~ s/\r\n/\n/g;

    # now check for UTF-8 correctness, it must hold

    return $err->("<?badinput?>") unless LJ::text_in($form);

    $init->{unknown8bit} = 0;
    unless (LJ::is_ascii($form->{'body'}) && LJ::is_ascii($form->{'subject'})) {
        if ($LJ::UNICODE) {
            # no need to check if they're well-formed, we did that above
        } else {
            # so rest of site can change chars to ? marks until
            # default user's encoding is set.  (legacy support)
            $init->{unknown8bit} = 1;
        }
    }

    my ($bl, $cl) = LJ::text_length($form->{'body'});
    if ($cl > LJ::CMAX_COMMENT) {
        $err->(BML::ml("$SC.error.manychars", {'current'=>$cl, 'limit'=>LJ::CMAX_COMMENT}));
    } elsif ($bl > LJ::BMAX_COMMENT) {
        $err->(BML::ml("$SC.error.manybytes", {'current'=>$bl, 'limit'=>LJ::BMAX_COMMENT}));
    }
    # the Subject can be silently shortened, no need to reject the whole comment
    $form->{'subject'} = LJ::text_trim($form->{'subject'}, 100, 100);

    my $subjecticon = "";
    if ($form->{'subjecticon'} ne "none" || $form->{'subjecticon'} ne "") {
        $subjecticon = LJ::trim(lc($form->{'subjecticon'}));
    }

    # figure out whether to post this comment screened
    my $state = 'A';
    if ($journalu->{'opt_whoscreened'} eq 'A' ||
        ($journalu->{'opt_whoscreened'} eq 'R' && ! $up) ||
        ($journalu->{'opt_whoscreened'} eq 'F' && !($up && LJ::is_friend($journalu, $up)))) {
        $state = 'S';
    }

    my $parent = {
        state     => $parpost->{state},
        talkid    => $partid,
    };
    my $comment = {
        u               => $up,
        usertype        => $form->{'usertype'},
        subject         => $form->{'subject'},
        body            => $form->{'body'},
        unknown8bit     => $init->{unknown8bit},
        subjecticon     => $subjecticon,
        preformat       => $form->{'prop_opt_preformatted'},
        picture_keyword => $form->{'prop_picture_keyword'},
        state           => $state,
    };

    $init->{item} = $item;
    $init->{parent} = $parent;
    $init->{comment} = $comment;

    return undef if @$errret;
    return $init;
}

sub post_comment {
    my ($entryu, $journalu, $comment, $parent, $item, $errref) = @_;

    # unscreen the parent comment if needed
    if ($parent->{state} eq 'S') {
        LJ::Talk::unscreen_comment($journalu, $item->{itemid}, $parent->{talkid});
        $parent->{state} = 'A';
    }

    # check for duplicate entry (double submission)
    # Note:  we don't do it inside a locked section like ljprotocol.pl's postevent,
    # so it's not perfect, but it works pretty well.
    my $posterid = $comment->{u} ? $comment->{u}{userid} : 0;
    my $jtalkid;

    # check for dup ID in memcache.
    my $memkey;
    if (@LJ::MEMCACHE_SERVERS) {
        my $md5_b64 = Digest::MD5::md5_base64(
            join(":", ($comment->{body}, $comment->{subject},
                       $comment->{subjecticon}, $comment->{preformat},
                       $comment->{picture_keyword})));
        $memkey = [$journalu->{userid}, "tdup:$journalu->{userid}:$item->{itemid}-$posterid-$md5_b64" ];
        $jtalkid = LJ::MemCache::get($memkey);
    }

    # they don't have a duplicate...
    unless ($jtalkid) {
        # XXX do select and delete $talkprop{'picture_keyword'} if they're lying
        my $pic = LJ::get_pic_from_keyword($comment->{u}, $comment->{picture_keyword});
        delete $comment->{picture_keyword} unless $pic && $pic->{'state'} eq 'N';
        $comment->{pic} = $pic;

        # put the post in the database
        my $ditemid = $item->{itemid}*256 + $item->{anum};
        $jtalkid = enter_comment($journalu, $parent, $item, $comment, $errref);
        return 0 unless $jtalkid;

        # save its identifying characteristics to protect against duplicates.
        LJ::MemCache::set($memkey, $jtalkid+0, time()+60*10);

        # send some emails
        mail_comments($entryu, $journalu, $parent, $comment, $item);

        # log the event
        # this function doesn't do anything.
        # LJ::event_register($dbcm, "R", $journalu->{'userid'}, $ditemid);
        # FUTURE: log events type 'T' (thread) up to root
    }

    # the caller wants to know the comment's talkid.
    $comment->{talkid} = $jtalkid;

    # cluster tracking
    LJ::mark_user_active($comment->{u}, 'comment');

    return 1;
}

# XXXevan:  this function should have its functionality migrated to talkpost.
# because of that, it's probably not worth the effort to make it not mangle $form...
sub make_preview {
    my ($talkurl, $cookie_auth, $form) = @_;
    my $ret = "";

    my $cleansubject = $form->{'subject'};
    LJ::CleanHTML::clean_subject(\$cleansubject);

    $ret .= "<?h1 $BML::ML{'/talkpost_do.bml.preview.title'} h1?><?p $BML::ML{'/talkpost_do.bml.preview'} p?><?hr?>";
    $ret .= "<div align=\"center\"><b>(<a href=\"$talkurl\">$BML::ML{'talk.commentsread'}</a>)</b></div>";

    my $event = $form->{'body'};
    my $spellcheck_html;
    if ($LJ::SPELLER && $form->{'do_spellcheck'}) {
        my $s = new LJ::SpellCheck { 'spellcommand' => $LJ::SPELLER,
                                     'color' => '<?hotcolor?>', };
        $spellcheck_html = $s->check_html(\$event);
    }
    LJ::CleanHTML::clean_comment(\$event, $form->{'prop_opt_preformatted'});

    $ret .= "$BML::ML{'/talkpost_do.bml.preview.subject'} " . LJ::ehtml($cleansubject) . "<hr />\n";
    if ($spellcheck_html) {
        $ret .= $spellcheck_html;
        $ret .= "<p>";
    } else {
        $ret .= $event;
    }

    $ret .= "<hr />";
    $ret .= "<div style='width: 90%'><form method='post'><p>\n";
    $ret .= "<input name='subject' size='50' maxlength='100' value='" . LJ::ehtml($form->{'subject'}) . "' /><br />";
    $ret .= "<textarea class='textbox' rows='10' cols='50' wrap='soft' name='body' style='width: 100%'>";
    $ret .= LJ::ehtml($form->{'body'});
    $ret .= "</textarea></p>";

    # change mode:
    delete $form->{'submitpreview'}; $form->{'submitpost'} = 1;
    if ($cookie_auth) {
        $form->{'usertype'} = "cookieuser";
        delete $form->{'userpost'};
    }
    delete $form->{'do_spellcheck'};
    foreach (keys %$form) {
        $ret .= LJ::html_hidden($_, $form->{$_})
            unless $_ eq 'body' || $_ eq 'subject' || $_ eq 'prop_opt_preformatted';
    }

    $ret .= "<br /><input type='submit' value='$BML::ML{'/talkpost_do.bml.preview.submit'}' />\n";
    $ret .= "<input type='submit' name='submitpreview' value='$BML::ML{'talk.btn.preview'}' />\n";
    if ($LJ::SPELLER) {
        $ret .= "<input type='checkbox' name='do_spellcheck' value='1' id='spellcheck' /> <label for='spellcheck'>$BML::ML{'talk.spellcheck'}</label>";
    }
    $ret .= "<p>";
    $ret .= "$BML::ML{'/talkpost.bml.opt.noautoformat'} ".
        LJ::html_check({ 'name' => 'prop_opt_preformatted', 
                         selected => $form->{'prop_opt_preformatted'} });
    $ret .= LJ::help_icon("noautoformat", " ");
    $ret .= "</p>";

    $ret .= "<p> <?de $BML::ML{'/talkpost.bml.allowedhtml'}: ";
    foreach (sort &LJ::CleanHTML::get_okay_comment_tags()) {
        $ret .= "&lt;$_&gt; ";
    }
    $ret .= "de?> </p>";

    $ret .= "</form></div>";
    return $ret;
}

# more anti-spammer rate limiting.
sub check_rate {
    my $remote = shift;

    # we require memcache to do rate limiting efficiently
    return 1 unless @LJ::MEMCACHE_SERVERS;

    my $ip = LJ::get_remote_ip();
    my $now = time();
    my @watch;

    # registered human (or human-impersonating robot)
    push @watch, ["talklog:$remote->{userid}", $LJ::RATE_COMMENT_AUTH ||
                  [ [200,3600], [20,60] ],
                  ] if $remote;

    # anonymous (robot or human)
    push @watch, ["talklog:$ip", $LJ::RATE_COMMENT_ANON ||
                  [ [300,3600], [200,1800], [150,900], [15,60] ]
                  ] unless $remote;

    my $too_fast = 0;

  WATCH:
    foreach my $watch (@watch) {
        my ($key, $rates) = ($watch->[0], $watch->[1]);
        my $max_period = $rates->[0]->[1];
        
        my $log = LJ::MemCache::get($key);
        my $DATAVER = "1";
        
        # parse the old log
        my @times;
        if (length($log) % 4 == 1 && substr($log,0,1) eq $DATAVER) {
            my $ct = (length($log)-1) / 4;
            for (my $i=0; $i<$ct; $i++) {
                my $time = unpack("N", substr($log,$i*4+1,4));
                push @times, $time if $time > $now - $max_period;
            }
        }
        
        # add this event
        push @times, $now;
        
        # check rates
        foreach my $rate (@$rates) {
            my ($allowed, $period) = ($rate->[0], $rate->[1]);
            my $events = scalar grep { $_ > $now-$period } @times;
            if ($events > $allowed) {
                $too_fast = 1;
                
                if ($LJ::DEBUG_TALK_RATE && 
                    LJ::MemCache::add("warn:$key", 1, 600)) {
                    LJ::send_mail({
                        'to' => $LJ::DEBUG_TALK_RATE,
                        'from' => $LJ::ADMIN_EMAIL,
                        'fromname' => $LJ::SITENAME,
                        'charset' => 'utf-8',
                        'subject' => "talk spam: $key",
                        'body' => "talk spam from $key:\n\n    $events comments > $allowed allowed / $period secs",
                    });
                }

                return 0 if $LJ::ANTI_TALKSPAM;
                last WATCH;
            }
        }
        
        # build the new log
        my $newlog = $DATAVER;
        foreach (@times) {
            $newlog .= pack("N", $_);
        }
        
        LJ::MemCache::set($key, $newlog, $max_period);
    }

    return 1;
}

1;
