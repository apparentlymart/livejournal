#!/usr/bin/perl
#

use strict;
package LJ::S2;

sub DayPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "DayPage";
    $p->{'view'} = "day";
    $p->{'entries'} = [];

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $dbcr;
    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }

    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) .
            "/calendar" . $opts->{'pathextra'};
        return 1;
    }

    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\">\n";
    }

    my %FORM = ();
    LJ::decode_url_string($opts->{'args'}, \%FORM);

    my $month = $FORM{'month'};
    my $day = $FORM{'day'};
    my $year = $FORM{'year'};
    my @errors = ();

    if ($opts->{'pathextra'} =~ m!^/(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
        ($month, $day, $year) = ($2, $3, $1);
    }
    
    $opts->{'errors'} = [];
    if ($year !~ /^\d+$/) { push @{$opts->{'errors'}}, "Corrupt or non-existant year."; }
    if ($month !~ /^\d+$/) { push @{$opts->{'errors'}}, "Corrupt or non-existant month."; }
    if ($day !~ /^\d+$/) { push @{$opts->{'errors'}}, "Corrupt or non-existant day."; }
    if ($month < 1 || $month > 12 || int($month) != $month) { push @{$opts->{'errors'}}, "Invalid month."; }
    if ($year < 1970 || $year > 2038 || int($year) != $year) { push @{$opts->{'errors'}}, "Invalid year: $year"; }
    if ($day < 1 || $day > 31 || int($day) != $day) { push @{$opts->{'errors'}}, "Invalid day."; }
    if (scalar(@{$opts->{'errors'}})==0 && $day > LJ::days_in_month($month, $year)) { push @{$opts->{'errors'}}, "That month doesn't have that many days."; }
    return if @{$opts->{'errors'}};

    $p->{'date'} = Date($year, $month, $day);
    
    my @itemids = ();

    my $secwhere = "AND security='public'";
    if ($remote) {
        if ($remote->{'userid'} == $u->{'userid'}) {
            $secwhere = "";   # see everything
        } elsif ($remote->{'journaltype'} eq 'P') {
            my $gmask = $dbr->selectrow_array("SELECT groupmask FROM friends WHERE userid=$u->{'userid'} AND friendid=$remote->{'userid'}");
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    my ($sth, $logdb);
    if ($u->{'clusterid'}) { 
        $logdb = LJ::get_cluster_reader($u);
        unless ($logdb) {
            push @{$opts->{'errors'}}, "Database temporarily unavailable";
            return;
        }
        $sth = $logdb->prepare("SELECT jitemid FROM log2 WHERE journalid=$u->{'userid'} ".
                               "AND year=$year AND month=$month AND day=$day $secwhere ".
                               "ORDER BY eventtime LIMIT 200");
    } else {
        $logdb = $dbr;
        $sth = $logdb->prepare("SELECT itemid FROM log WHERE ownerid=$u->{'userid'} ".
                               "AND year=$year AND month=$month AND day=$day $secwhere ".
                               "ORDER BY eventtime LIMIT 200");
    }
    $sth->execute;

    push @itemids, $_ while ($_ = $sth->fetchrow_array);

    my $itemid_in = join(", ", map { $_+0; } @itemids);

    ### load the log properties
    my %logprops = ();
    my $logtext;
    if ($u->{'clusterid'}) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
        $logtext = LJ::get_logtext2($u, @itemids);
    } else {
        LJ::load_log_props($dbs, \@itemids, \%logprops);
        $logtext = LJ::get_logtext($dbs, @itemids);
    }
    LJ::load_moods($dbs);

    # load the log items
    my $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    if ($u->{'clusterid'}) {
        $sth = $logdb->prepare("SELECT posterid, jitemid, security, replycount, DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum ".
                               "FROM log2 WHERE journalid=$u->{'userid'} AND jitemid IN ($itemid_in) ORDER BY eventtime, logtime");
    } else {
        $sth = $dbr->prepare("SELECT posterid, itemid, security, replycount, DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart' ".
                             "FROM log WHERE itemid IN ($itemid_in) ORDER BY eventtime, logtime");
    }
    $sth->execute;

    my @items;
    push @items, $_ while $_ = $sth->fetchrow_hashref;

    my (%apu, %apu_lite);  # alt poster users; UserLite objects
    foreach (@items) {
        next unless $_->{'posterid'} != $u->{'userid'};
        $apu{$_->{'posterid'}} = undef;
    }
    if (%apu) {
        my $in = join(',', keys %apu);
        my $sth = $dbr->prepare("SELECT userid, user, defaultpicid, statusvis, name, journaltype ".
                                "FROM user WHERE userid IN ($in)");
        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            $apu{$_->{'userid'}} = $_;
            $apu_lite{$_->{'userid'}} = UserLite($_);
        }
    }

    my $userlite_journal = UserLite($u);

    foreach my $item (@items)
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount, $anum) = 
            map { $item->{$_} } qw(posterid jitemid security alldatepart replycount anum);

        my $subject = $logtext->{$itemid}->[0];
        my $text = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($dbs, $u, \$subject, \$text, $logprops{$itemid});
	}

        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $u->{'clusterid'} ? ($itemid*256 + $anum) : $itemid;
        my $itemargs = $u->{'clusterid'} ? "journal=$user&itemid=$ditemid" : "itemid=$ditemid";

        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $anum), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$text);

        my $nc;
        $nc = "&nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

        my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs$nc";
        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
            'count' => $replycount,
            'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! $logprops{$itemid}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$itemid}->{'hasscreened'} && ($remote->{'user'} eq $u->{'user'}|| LJ::check_priv($dbs, $remote, "sharedjournal", $user))) ? 1 : 0,
        });
        
        my $userlite_poster = $userlite_journal;
        my $userpic = $p->{'journal'}->{'default_pic'};
        if ($u->{'userid'} != $posterid) {
            $userlite_poster = $apu_lite{$posterid} or die "No apu_lite for posterid=$posterid";
            $userpic = Image_userpic($apu{$posterid}, 0, $logprops{$itemid}->{'picture_keyword'});
        }

        my $entry = Entry($u, {
            'subject' => $subject,
            'text' => $text,
            'dateparts' => $alldatepart,
            'security' => $security,
            'props' => $logprops{$itemid},
            'itemid' => $ditemid,
            'journal' => $userlite_journal,
            'poster' => $userlite_poster,
            'comments' => $comments,
            'userpic' => $userpic,
        });

        push @{$p->{'entries'}}, $entry;
    }

    if (@{$p->{'entries'}}) {
        $p->{'has_entries'} = 1;
        $p->{'entries'}->[0]->{'new_day'} = 1;
        $p->{'entries'}->[-1]->{'end_day'} = 1;
    }

    # calculate previous day
    my $pdyear = $year;
    my $pdmonth = $month;
    my $pdday = $day-1;
    if ($pdday < 1)
    {
        if (--$pdmonth < 1)
        {
          $pdmonth = 12;
          $pdyear--;
        }
        $pdday = LJ::days_in_month($pdmonth, $pdyear);
    }

    # calculate next day
    my $nxyear = $year;
    my $nxmonth = $month;
    my $nxday = $day+1;
    if ($nxday > LJ::days_in_month($nxmonth, $nxyear))
    {
        $nxday = 1;
        if (++$nxmonth > 12) { ++$nxyear; $nxmonth=1; }
    }
    
    $p->{'prev_url'} = "$u->{'_journalbase'}/day/" . sprintf("%04d/%02d/%02d", $pdyear, $pdmonth, $pdday); 
    $p->{'prev_date'} = Date($pdyear, $pdmonth, $pdday);
    $p->{'next_url'} = "$u->{'_journalbase'}/day/" . sprintf("%04d/%02d/%02d", $nxyear, $nxmonth, $nxday); 
    $p->{'next_date'} = Date($nxyear, $nxmonth, $nxday);

    return $p;
}

1;
