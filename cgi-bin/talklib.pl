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
    return unless defined $pics->{'pic'}->{$id};
    my $p = $pics->{'pic'}->{$id};
    my $pfx = "$LJ::IMGPREFIX/talk";
    return "<img src=\"$LJ::IMGPREFIX/talk/$p->{'img'}\" border='0' ".
        "width='$p->{'w'}' height='$p->{'h'}' valign='middle' />";
}

sub link_bar
{
    my $dbs = shift;
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

    my $jarg = $u->{'clusterid'} ? "journal=$u->{'user'}&" : "";
    my $jargent = $u->{'clusterid'} ? "journal=$u->{'user'}&amp;" : "";

    # << Previous
    push @linkele, $mlink->("/go.bml?${jargent}itemid=$itemid&amp;dir=prev", "prev_entry");
    $$headref .= "<link href='/go.bml?${jargent}itemid=$itemid&amp;dir=prev' rel='Previous' />\n";
    
    # memories
    unless ($LJ::DISABLED{'memories'}) {
        push @linkele, $mlink->("/tools/memadd.bml?${jargent}itemid=$itemid", "memadd");
    }
    
    if (defined $remote && ($remote->{'user'} eq $u->{'user'} ||
                            $remote->{'user'} eq $up->{'user'} || 
                            LJ::check_rel($dbs, $u, $remote, 'A')))
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
    my ($dbs, $form) = @_;
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
        $ju = LJ::load_user($dbs, $journal);
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
            my $newinfo = LJ::get_newids($dbs, 'L', $itemid);
            if ($newinfo) {
                $ju = LJ::load_userid($dbs, $newinfo->[0]);
                $init->{'clustered'} = 1;
                $init->{'itemid'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
                if ($form->{'thread'}) {
                    my $tinfo = LJ::get_newids($dbs, 'T', $init->{'thread'});
                    $init->{'thread'} = $tinfo->[1] if $tinfo;
                }
            } else {
                my $jid = LJ::dbs_selectrow_array($dbs, "SELECT ownerid FROM log WHERE itemid=$itemid");
                return { 'error' => BML::ml('talk.error.noentry')} unless $jid;
                $ju = LJ::load_userid($dbs, $jid);
            }
        } elsif ($form->{'replyto'}) {
            my $replyto = $form->{'replyto'}+0;
            my $newinfo = LJ::get_newids($dbs, 'T', $replyto);
            if ($newinfo) {
                $ju = LJ::load_userid($dbs, $newinfo->[0]);
                $init->{'replyto'} = $newinfo->[1];
                $init->{'oldurl'} = 1;
            } else {
                # guess it's on cluster 0, so find out what journal.
                my $jid = LJ::dbs_selectrow_array($dbs, "SELECT journalid FROM talk WHERE talkid=$replyto");
                return { 'error' => BML::ml('talk.error.noentry')} unless $jid;
                $ju = LJ::load_userid($dbs, $jid);
            }
        }
    }

    $init->{'journalu'} = $ju;
    return $init;
}

sub get_journal_item
{
    my ($dbs, $dbcs, $u, $itemid) = @_;
    my $clustered = $u->{'clusterid'};
    my $sql;
    if ($clustered) {
        $sql = "SELECT journalid AS 'ownerid', posterid, eventtime, security, allowmask, ".
            "UNIX_TIMESTAMP()-UNIX_TIMESTAMP(logtime) AS 'secondsold', anum ".
            "FROM log2 WHERE journalid=$u->{'userid'} AND jitemid=$itemid";
    } else {
        $sql = "SELECT ownerid, posterid, eventtime, security, allowmask, ".
            "UNIX_TIMESTAMP()-UNIX_TIMESTAMP(logtime) AS 'secondsold' ".
            "FROM log WHERE itemid=$itemid";
    }
    my $item = LJ::dbs_selectrow_hashref($dbcs, $sql);
    return undef unless $item;
    $item->{'itemid'} = $itemid;

    my $lt = $clustered ? LJ::get_logtext2($u, $itemid) : LJ::get_logtext($dbcs, $itemid);
    my $v = $lt->{$itemid};
    $item->{'subject'} = $v->[0];
    $item->{'event'} = $v->[1];

    ### load the log properties
    my %logprops = ();
    if ($clustered) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($dbcs->{'reader'}, $u->{'userid'}, [ $itemid ], \%logprops);
    } else {
        LJ::load_log_props($dbcs, [ $itemid ], \%logprops);
    }
    $item->{'logprops'} = \%logprops;

    if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
        LJ::item_toutf8($dbs, $u, \$item->{'subject'}, \$item->{'event'},
                        $item->{'logprops'}->{$itemid});
    }
    return $item;
}

sub check_viewable
{
    my ($dbs, $remote, $item, $form, $errref) = @_;
    
    my $err = sub {
        $$errref = "<?h1 <?_ml Error _ml?> h1?><?p $_[0] p?>";
        return 0;
    };

    unless (LJ::can_view($dbs, $remote, $item)) 
    {
        if ($form->{'viewall'} && LJ::check_priv($dbs, $remote, "viewall")) {
            LJ::statushistory_add($dbs, $item->{'posterid'}, $remote->{'userid'}, 
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
    my ($dbs, $remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $userpost ||
                $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq $up->{'user'} ||
                LJ::check_rel($dbs, $u, $remote, 'A');
    return 0;
}

sub can_screen {
    my ($dbs, $remote, $u, $up, $userpost) = @_;
    return 0 unless $remote;
    return 1 if $remote->{'user'} eq $u->{'user'} ||
                $remote->{'user'} eq $up->{'user'} ||
                LJ::check_rel($dbs, $u, $remote, 'A');
    return 0;
}

sub can_unscreen {
    return LJ::Talk::can_screen(@_);
}

sub can_view_screened {
    return LJ::Talk::can_delete(@_);
}

sub update_commentalter {
    my ($dbs, $dbcs, $u, $itemid) = @_;
    my $dbcm = $dbcs->{'dbh'};
    my $clustered = $u->{'clusterid'};
    my $userid = $u->{'userid'};
    my $prop = LJ::get_prop("log", "commentalter");

    $itemid = $itemid + 0;

    if ($clustered) {
        $dbcm->do("REPLACE INTO logprop2 (journalid, jitemid, propid, value) VALUES (?, ?, ?, UNIX_TIMESTAMP())", undef, $userid, $itemid, $prop->{'id'});
    } else {
        $dbcm->do("REPLACE INTO logprop (itemid, propid, value) VALUES (?, ?, UNIX_TIMESTAMP())", undef, $itemid, $prop->{'id'});
    }
}

sub screen_comment {
    my $dbs = shift;
    my $dbcs = shift;
    my $u = shift;
    my $itemid = shift(@_) + 0;

    my $in = join (',', map { $_+0 } @_);
    return unless $in;

    my $dbcm = $dbcs->{'dbh'};
    my $clustered = $u->{'clusterid'};
    my $userid = $u->{'userid'} + 0;
    my $prop = LJ::get_prop("log", "hasscreened");

    if ($clustered) {
        my $updated = $dbcm->do("UPDATE talk2 SET state='S' ".
                                "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                "AND nodetype='L' AND nodeid=$itemid ".
                                "AND state NOT IN ('S','D')");
        if ($updated > 0) {
            $dbcm->do("UPDATE log2 SET replycount=replycount-$updated WHERE journalid=$userid AND jitemid=$itemid");
            $dbcm->do("REPLACE INTO logprop2 (journalid, jitemid, propid, value) VALUES ($userid, $itemid, $prop->{'id'}, '1')");
        }
    } else {
        my $updated = $dbcm->do("UPDATE talk SET state='S' WHERE talkid IN ($in) AND state NOT IN ('S','D')");
        if ($updated > 0) {
            $dbcm->do("UPDATE log SET replycount=replycount-$updated WHERE itemid=$itemid");
            $dbcm->do("REPLACE INTO logprop (itemid, propid, value) VALUES ($itemid, $prop->{'id'}, '1')");
        }
    }

    LJ::Talk::update_commentalter($dbs, $dbcs, $u, $itemid);
    return;
}

sub unscreen_comment {
    my $dbs = shift;
    my $dbcs = shift;
    my $u = shift;
    my $itemid = shift(@_) + 0;

    my $in = join (',', map { $_+0 } @_);
    return unless $in;

    my $dbcm = $dbcs->{'dbh'};
    my $dbcr = $dbcs->{'reader'};
    my $clustered = $u->{'clusterid'};
    my $userid = $u->{'userid'} + 0;
    my $prop = LJ::get_prop("log", "hasscreened");

    if ($clustered) {
        my $updated = $dbcm->do("UPDATE talk2 SET state='A' ".
                                "WHERE journalid=$userid AND jtalkid IN ($in) ".
                                "AND nodetype='L' AND nodeid=$itemid ".
                                "AND state='S'");
        if ($updated > 0) {
            $dbcm->do("UPDATE log2 SET replycount=replycount+$updated WHERE journalid=$userid AND jitemid=$itemid");

            my $hasscreened = $dbcm->selectrow_array("SELECT COUNT(*) FROM talk2 " .
                                                     "WHERE journalid=$userid AND nodeid=$itemid AND nodetype='L' AND state='S'");
            $dbcm->do("DELETE FROM logprop2 WHERE journalid=$userid AND jitemid=$itemid AND propid=$prop->{'id'}")
                unless $hasscreened;
        }
    } else {
        my $updated = $dbcm->do("UPDATE talk SET state='A' WHERE talkid IN ($in) AND state='S'");
        if ($updated > 0) {
            $dbcm->do("UPDATE log SET replycount=replycount+$updated WHERE itemid=$itemid");
            my $hasscreened = $dbcr->selectrow_array("SELECT COUNT(*) FROM talk WHERE ".
                                                     "nodeid=$itemid AND nodetype='L' AND state='S'");
            $dbcm->do("DELETE FROM logprop WHERE itemid=$itemid AND propid=$prop->{'id'}")
                unless $hasscreened;
        }
    }

    LJ::Talk::update_commentalter($dbs, $dbcs, $u, $itemid);
    return;
}


1;
