#!/usr/bin/perl
#

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
	"width='$p->{'w'}' height='$p->{'h'}' valign='middle'>";
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
    $$headref .= "<link href='/go.bml?${jargent}itemid=$itemid&amp;dir=prev' rel='Previous'>\n";
    
    # memories
    push @linkele, $mlink->("/tools/memadd.bml?${jargent}itemid=$itemid", "memadd");
    
    if (defined $remote && ($remote->{'user'} eq $u->{'user'} ||
			    $remote->{'user'} eq $up->{'user'} || 
			    LJ::check_priv($dbs, $remote, "sharedjournal", $u->{'user'})))
    {
	push @linkele, $mlink->("/editjournal_do.bml?${jargent}itemid=$itemid", "editentry");
    }
    
    if ($u->{'opt_showtopicstuff'} ne "N") {
	push @linkele, $mlink->("/topics/additem.bml?${jargent}itemid=$itemid", "topicadd");
    }
    
    push @linkele, $mlink->("/tools/tellafriend.bml?${jargent}itemid=$itemid", "tellfriend");
    
    ## >>> Next
    push @linkele, $mlink->("/go.bml?${jargent}itemid=$itemid&amp;dir=next", "next_entry");
    
    if (@linkele) {
	$ret .= "(=STANDOUT <table><tr><td valign='middle'>";
	$ret .= join("&nbsp;&nbsp;", @linkele);
	$ret .= "</td></tr></table> STANDOUT=)";
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
    
    if ($journal) {
	# they specified a journal argument, which indicates new style.
	$ju = LJ::load_user($dbs, $journal);
	$init->{'clustered'} = 1;
	foreach (qw(itemid replyto)) {
	    next unless $init->{$_};
	    $init->{'anum'} = $init->{$_} % 256;
	    $init->{$_} = int($init->{$_} / 256);
	    last;
	}
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
	    } else {
		my $jid = LJ::dbs_selectrow_array($dbs, "SELECT ownerid FROM log WHERE itemid=$itemid");
		$ju = LJ::load_userid($dbs, $jid);
	    }
	} elsif ($form->{'replyto'}) {
	    my $replyto = $form->{'replyto'}+0;
	    my $newinfo = LJ::get_newids($dbs, 'T', $replyto);
	    if ($newinfo) {
		$ju = LJ::load_userid($dbs, $newinfo->[0]);
		$init->{'replyto'} = $newinfo->[1];
	    } else {
		# guess it's on cluster 0, so find out what journal.
		my $jid = LJ::dbs_selectrow_array($dbs, "SELECT journalid FROM talk WHERE talkid=$replyto");
		$ju = LJ::load_userid($dbs, $jid);
	    }
	}
    }

    $init->{'journalu'} = $ju;
    return $init;
}

sub topic_links
{
    my ($dbs, $u, $itemid) = @_;
    my $ret;
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return if $u->{'clusterid'};  # FIXME: finish topic support for cluster-ers

    my $in_topic = 0;
    my $sth = $dbr->prepare("SELECT tptopid, status FROM topic_map WHERE itemid=$itemid");
    $sth->execute;
    while (my ($tptopid, $status) = $sth->fetchrow_array)
    {
	next unless $status eq "on";
	unless ($in_topic) {
	    $in_topic = 1;
	    $ret .= "<b>Read similar journal entries:</b><br />";
	}
	
	# TODO: LJ::Topic doesn't yet support $dbs/$dbarg
	my @hier = LJ::Topic::get_hierarchy($dbh, { 'topid' => $tptopid });
	$ret .= "<b>";
	$ret .= join(" : ", map { "<a href=\"$_->{'url'}\">$_->{'name'}</a>"; } @hier);
	$ret .= "</b><br />";
    }
    return $ret;
}

sub get_journal_item
{
    my ($dbcs, $u, $itemid) = @_;
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
    return $item;
}

sub check_viewable
{
    my ($dbs, $remote, $item, $form, $errref) = @_;
    
    my $err = sub {
	$$errref = "(=H1 Error H1=)(=P $_[0] P=)";
	return 0;
    };

    unless (LJ::can_view($dbs, $remote, $item)) 
    {
	if ($form->{'viewall'} && LJ::check_priv($dbs, $remote, "viewall")) {
	    LJ::statushistory_add($dbs, $item->{'posterid'}, $remote->{'userid'}, 
				  "viewall", "itemid = $item->{'itemid'}");
	} else {
	    return $err->("You must be logged in to view this protected entry.")
		unless defined $remote;
	    return $err->("You are not authorized to view this protected entry.");
	}
    }

    return 1;
}

1;
