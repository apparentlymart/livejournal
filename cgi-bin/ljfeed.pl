#!/usr/bin/perl

use strict;

package LJ::Feed;

my %feedtypes = (
    rss  => \&create_view_rss,
    atom => \&create_view_atom,
);

sub make_feed
{
    my ($r, $u, $remote, $opts) = @_;

    $opts->{pathextra} =~ s!^/(\w+)!!;
    my $feedtype = $1;
    my $viewfunc = $feedtypes{$feedtype};

    unless ($viewfunc) {
        $opts->{'handler_return'} = 404;
        return undef;
    }

    $r->notes('codepath' => "feed.$feedtype") if $r;

    my $dbr = LJ::get_db_reader();

    # for syndicated accounts, redirect to the syndication URL
    if ($u->{'journaltype'} eq 'Y') {
        my $synurl = $dbr->selectrow_array("SELECT synurl FROM syndicated WHERE userid=$u->{'userid'}");
        unless ($synurl) {
            return 'No syndication URL available.';
        }
        $opts->{'redir'} = $synurl;
        return undef;
    }

    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'}) . "/data/$feedtype";
        return undef;
    }

    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    ## load the itemids
    my @itemids;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'remote' => $remote,
        'userid' => $u->{'userid'},
        'itemshow' => 25,
        'order' => "logtime",
        'itemids' => \@itemids,
        'friendsview' => 1,           # this returns rlogtimes
        'dateformat' => "S2",         # S2 format time format is easier
    });

    $opts->{'contenttype'} = 'text/xml; charset='.$opts->{'saycharset'};

    ### load the log properties
    my %logprops = ();
    my $logtext;
    my $logdb = LJ::get_cluster_reader($u);
    LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);

    # set last-modified header, then let apache figure out
    # whether we actually need to send the feed.
    my $lastmod = 0;
    foreach my $item (@items) {
        # revtime of the item.
        my $revtime = $logprops{$item->{itemid}}->{revtime};
        $lastmod = $revtime if $revtime > $lastmod;

        # if we don't have a revtime, use the logtime of the item.
        unless ($revtime) {
            my $itime = $LJ::EndOfTime - $item->{rlogtime};
            $lastmod = $itime if $itime > $lastmod;
        }
    }
    $r->set_last_modified($lastmod) if $lastmod;

    # regarding $r->set_etag:
    # http://perl.apache.org/docs/general/correct_headers/correct_headers.html#Entity_Tags
    # It is strongly recommended that you do not use this method unless you
    # know what you are doing. set_etag() is expecting to be used in
    # conjunction with a static request for a file on disk that has been
    # stat()ed in the course of the current request. It is inappropriate and
    # "dangerous" to use it for dynamic content.
    if ((my $status = $r->meets_conditions) != Apache::Constants::OK()) {
        $opts->{handler_return} = $status;
        return undef;
    }

    # some data used throughout the channel
    my $journalinfo = {
        u         => $u,
        link      => LJ::journal_base($u) . "/",
        title     => LJ::exml($u->{journaltitle} || $u->{name}) || $u->{user},
        subtitle  => LJ::exml($u->{journalsubtitle} || $u->{name}) || $u->{user},
        builddate => LJ::time_to_http($LJ::EndOfTime - $items[0]->{'rlogtime'}),
    };

    # email address of journal owner, but respect their privacy settings
    if ($u->{'allow_contactshow'} eq "Y" && $u->{'opt_whatemailshow'} ne "N" && $u->{'opt_mangleemail'} ne "Y") {
        my $cemail;
        
        # default to their actual email
        $cemail = $u->{'email'};
        
        # use their livejournal email if they have one
        if ($LJ::USER_EMAIL && $u->{'opt_whatemailshow'} eq "L" &&
            LJ::get_cap($u, "useremail") && ! $u->{'no_mail_alias'}) {

            $cemail = "$u->{'user'}\@$LJ::USER_DOMAIN";
        } 

        # clean it up since we know we have one now
        $journalinfo->{email} = LJ::exml($cemail);
    }

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } @items], [$u]);

    my @cleanitems;
  ENTRY:
    foreach my $it (@items) 
    {
        # load required data
        my $itemid = $it->{'itemid'};

        next ENTRY if $posteru{$it->{'posterid'}} && $posteru{$it->{'posterid'}}->{'statusvis'} eq 'S';

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$logtext->{$itemid}->[0],
                            \$logtext->{$itemid}->[1], $logprops{$itemid});
        }

        # see if we have a subject and clean it
        my $subject = $logtext->{$itemid}->[0];
        if ($subject) {
            $subject =~ s/[\r\n]/ /g;
            LJ::CleanHTML::clean_subject_all(\$subject);
            $subject = LJ::exml($subject);
        }

        my $event = $logtext->{$itemid}->[1];

        # users without 'full_rss' get their logtext bodies truncated
        # do this now so that the html cleaner will hopefully fix html we break
        unless (LJ::get_cap($u, 'full_rss')) {
            my $trunc = LJ::text_trim($event, 0, 80);
            $event = "$trunc..." if $trunc ne $event;
        }

        # clean the event
        LJ::CleanHTML::clean_event(\$event, 
                                   { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'} });

        if ($event =~ /<lj-poll-(\d+)>/) {
            my $pollid = $1;
            my $name = $dbr->selectrow_array("SELECT name FROM poll WHERE pollid=?",
                                             undef, $pollid);

            if ($name) {
                LJ::Poll::clean_poll(\$name);
            } else {
                $name = "#$pollid";
            }

            $event =~ s!<lj-poll-$pollid>!<div><a href="$LJ::SITEROOT/poll/?id=$pollid">View Poll: $name</a></div>!g;
        }

        $event = LJ::exml($event);

        my $ditemid = $itemid*256 + $it->{'anum'};

        my $createtime = $LJ::EndOfTime - $it->{rlogtime};
        my $cleanitem = {
            itemid     => $itemid,
            ditemid    => $ditemid,
            subject    => $subject,
            event      => $event,
            createtime => $createtime,
            eventtime  => $it->{alldatepart},  # ugly: this is of a different format than the other two times.
            modtime    => $logprops{$itemid}->{revtime} || $createtime,
            comments   => ($logprops{$itemid}->{'opt_nocomments'} != 0),
        };
        push @cleanitems, $cleanitem;
    }

    return $viewfunc->($journalinfo, $u, $opts, \@cleanitems);
}

# the creator for the RSS XML syndication view
sub create_view_rss
{
    my ($journalinfo, $u, $opts, $cleanitems) = @_;

    my $ret;

    # header
    $ret .= "<?xml version='1.0' encoding='$opts->{'saycharset'}' ?>\n";
    $ret .= "<rss version='2.0'>\n";

    # channel attributes
    $ret .= "<channel>\n";
    $ret .= "  <title>$journalinfo->{title}</title>\n";
    $ret .= "  <link>$journalinfo->{link}</link>\n";
    $ret .= "  <description>$journalinfo->{title} - $LJ::SITENAME</description>\n";
    $ret .= "  <managingEditor>$journalinfo->{email}</managingEditor>\n" if $journalinfo->{email};
    $ret .= "  <lastBuildDate>$journalinfo->{builddate}</lastBuildDate>\n";
    $ret .= "  <generator>LiveJournal / $LJ::SITENAME</generator>\n";
    # TODO: add 'language' field when user.lang has more useful information

    ### image block, returns info for their current userpic
    if ($u->{'defaultpicid'}) {
        my $pic = {};
        LJ::load_userpics($pic, [$u->{'defaultpicid'}]);
        $pic = $pic->{$u->{'defaultpicid'}}; # flatten
        
        $ret .= "  <image>\n";
        $ret .= "    <url>$LJ::USERPIC_ROOT/$u->{'defaultpicid'}/$u->{'userid'}</url>\n";
        $ret .= "    <title>$journalinfo->{title}</title>\n";
        $ret .= "    <link>$journalinfo->{link}</link>\n";
        $ret .= "    <width>$pic->{'width'}</width>\n";
        $ret .= "    <height>$pic->{'height'}</height>\n";
        $ret .= "  </image>\n\n";
    }

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } @$cleanitems], [$u]);

    # output individual item blocks

    foreach my $it (@$cleanitems) 
    {
        my $itemid = $it->{itemid};
        my $ditemid = $it->{ditemid};
        $ret .= "<item>\n";
        $ret .= "  <guid isPermaLink='true'>$journalinfo->{link}$ditemid.html</guid>\n";
        $ret .= "  <pubDate>" . LJ::time_to_http($it->{createtime}) . "</pubDate>\n";
        $ret .= "  <title>$it->{subject}</title>\n" if $it->{subject};
        $ret .= "  <author>$journalinfo->{email}</author>" if $journalinfo->{email};
        $ret .= "  <link>$journalinfo->{link}$ditemid.html</link>\n";
        $ret .= "  <description>$it->{event}</description>\n";
        if ($it->{comments}) {
            $ret .= "  <comments>$journalinfo->{link}$ditemid.html</comments>\n";
        }
        # TODO: add author field with posterid's email address, respect communities
        $ret .= "</item>\n";
    }

    $ret .= "</channel>\n";
    $ret .= "</rss>\n";

    return $ret;
}

# the creator for the Atom view
sub create_view_atom
{
    my ($journalinfo, $u, $opts, $cleanitems) = @_;

    my $ret;

    # header
    $ret .= "<?xml version='1.0' encoding='$opts->{'saycharset'}' ?>\n";
    $ret .= "<feed version='0.3' xmlns='http://purl.org/atom/ns#'>\n";

    # attributes
    $ret .= "<title>$journalinfo->{title}</title>\n";
    $ret .= "<tagline>$journalinfo->{subtitle}</tagline>\n";
    $ret .= "<link rel='alternate' type='text/html' href='$journalinfo->{link}' />\n";

    # output individual item blocks

    foreach my $it (@$cleanitems) 
    {
        my $itemid = $it->{itemid};
        my $ditemid = $it->{ditemid};

        $ret .= "  <entry>\n";
        $ret .= "    <title>$it->{subject}</title>\n"; # include empty tag if we don't have a subject.
        $ret .= "    <id>urn:lj:$LJ::DOMAIN:atom1:$journalinfo->{u}{user}:$ditemid</id>\n";
        $ret .= "    <link rel='alternate' type='text/html' href='$journalinfo->{link}$ditemid.html' />\n";
        $ret .= "    <created>" . LJ::time_to_w3c($it->{createtime}, 'Z') . "</created>\n"
             if $it->{createtime} != $it->{modtime};

        my ($year, $mon, $mday, $hour, $min, $sec) = split(/ /, $it->{eventtime});
        $ret .= "    <issued>" .  sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
                                          $year, $mon, $mday,
                                          $hour, $min, $sec) .  "</issued>\n";
        $ret .= "    <modified>" . LJ::time_to_w3c($it->{modtime}, 'Z') . "</modified>\n";
        $ret .= "    <author>\n";
        $ret .= "      <name>" . LJ::exml($journalinfo->{u}{name}) . "</name>\n";
        $ret .= "      <email>$journalinfo->{editor}</email>\n" if $journalinfo->{editor};
        $ret .= "    </author>\n";
        # should rel be fragment?  or some other rel?  should it depend on whether we truncated?
        $ret .= "    <content type='text/html' mode='escaped' rel='fragment'>$it->{event}</content>\n";
        $ret .= "  </entry>\n";
    }

    $ret .= "</feed>\n";

    return $ret;
}

1;
