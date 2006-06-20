#!/usr/bin/perl
#

use strict;
use vars qw(%maint %maintinfo);
use lib "$ENV{'LJHOME'}/cgi-bin";  # extra XML::Encoding files in cgi-bin/XML/*
use XML::RSS;

require "ljprotocol.pl";
require "parsefeed.pl";
require "cleanhtml.pl";

$maintinfo{'synsuck'}{opts}{locking} = "per_host";
$maint{'synsuck'} = sub
{
    my $maxcount = shift || 0;
    my $verbose = $LJ::LJMAINT_VERBOSE;

    my %child_jobs; # child pid => [ userid, lock ]

    # get the next user to be processed
    my @all_users;
    my $get_next_user = sub {
        return shift @all_users if @all_users;

        # need to get some more rows
        my $dbh = LJ::get_db_writer();
        my $current_jobs = join(",", map { $dbh->quote($_->[0]) } values %child_jobs);
        my $in_sql = " AND u.userid NOT IN ($current_jobs)" if $current_jobs;
        my $sth = $dbh->prepare("SELECT u.user, s.userid, s.synurl, s.lastmod, " .
                                "       s.etag, s.numreaders, s.checknext " .
                                "FROM user u, syndicated s " .
                                "WHERE u.userid=s.userid AND u.statusvis='V' " .
                                "AND s.checknext < NOW()$in_sql " .
                                "LIMIT 500");
        $sth->execute;
        while (my $urow = $sth->fetchrow_hashref) {
            push @all_users, $urow;
        }

        return undef unless @all_users;
        return shift @all_users;
    };

    # fork and manage child processes
    my $max_threads = $LJ::SYNSUCK_MAX_THREADS || 1;
    print "[$$] PARENT -- using $max_threads workers\n" if $verbose;

    my $threads = 0;
    my $userct = 0;
    my $keep_forking = 1;
    while ( $maxcount == 0 || $userct < $maxcount ) {

        if ($threads < $max_threads && $keep_forking) {
            my $urow = $get_next_user->();
            unless ($urow) {
                $keep_forking = 0;
                next;
            }

            my $lockname = "synsuck-user-" . $urow->{user};
            my $lock = LJ::locker()->trylock($lockname);
            next unless $lock;
            print "Got lock on '$lockname'. Running\n" if $verbose;

            # spawn a new process
            if (my $pid = fork) {
                # we are a parent, nothing to do?
                $child_jobs{$pid} = [$urow->{'userid'}, $lock];
                $threads++;
                $userct++;
            } else {
                # handles won't survive the fork
                LJ::disconnect_dbs();
                LJ::SynSuck::update_feed($urow, $verbose);
                exit 0;
            }

        # wait for child(ren) to die
        } else {
            my $child = wait();
            last if $child == -1;
            delete $child_jobs{$child};
            $threads--;
        }
    }

    # Now wait on any remaining children so we don't leave zombies behind.
    while ( %child_jobs ) {
        my $child = wait();
        last if $child == -1;
        delete $child_jobs{ $child };
        $threads--;
    }

    print "[$$] $userct users processed\n" if $verbose;
    return;
};

package LJ::SynSuck;
use strict;
use HTTP::Status;

sub update_feed {
    my ($urow, $verbose) = @_;
    return unless $urow;

    my ($user, $userid, $synurl, $lastmod, $etag, $readers) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders);

    # we're a child process now, need to invalidate caches and
    # get a new database handle
    LJ::start_request();

    if (my $resp = get_content($urow, $verbose)) {
        process_content($urow, $resp, $verbose);
    }
}

sub delay {
    my ($userid, $minutes, $status) = @_;

    # add some random backoff to avoid waves building up
    $minutes += int(rand(5));

    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE syndicated SET lastcheck=NOW(), checknext=DATE_ADD(NOW(), ".
             "INTERVAL ? MINUTE), laststatus=? WHERE userid=?",
             undef, $minutes, $status, $userid);
    return undef;
}

sub get_content {
    my ($urow, $verbose) = @_;

    my ($user, $userid, $synurl, $lastmod, $etag, $readers) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders);

    my $dbh = LJ::get_db_writer();

    # see if things have changed since we last looked and acquired the lock.
    # otherwise we could 1) check work, 2) get lock, and between 1 and 2 another
    # process could do both steps.  we don't want to duplicate work already done.
    my $now_checknext = $dbh->selectrow_array("SELECT checknext FROM syndicated ".
                                              "WHERE userid=?", undef, $userid);
    return if $now_checknext ne $urow->{checknext};

    my $ua = LJ::get_useragent(role => 'syn_sucker');
    my $reader_info = $readers ? "; $readers readers" : "";
    $ua->agent("$LJ::SITENAME ($LJ::ADMIN_EMAIL; for $LJ::SITEROOT/users/$user/" . $reader_info . ")");

    print "[$$] Synsuck: $user ($synurl)\n" if $verbose;

    my $req = HTTP::Request->new("GET", $synurl);
    $req->header('If-Modified-Since', LJ::time_to_http($lastmod))
        if $lastmod;
    $req->header('If-None-Match', $etag)
        if $etag;

    my ($content, $too_big);
    my $res = eval {
        $ua->request($req, sub {
            if (length($content) > 1024*150) { $too_big = 1; return; }
            $content .= $_[0];
        }, 4096);
    };
    if ($@)       { return delay($userid, 120, "lwp_death"); }
    if ($too_big) { return delay($userid, 60, "toobig");     }

    if ($res->is_error()) {
        # http error
        print "HTTP error!\n" if $verbose;

        # overload parseerror here because it's already there -- we'll
        # never have both an http error and a parse error on the
        # same request
        delay($userid, 3*60, "parseerror");

        LJ::set_userprop($userid, "rssparseerror", $res->status_line());
        return;
    }

    # check if not modified
    if ($res->code() == RC_NOT_MODIFIED) {
        print "  not modified.\n" if $verbose;
        return delay($userid, $readers ? 60 : 24*60, "notmodified");
    }

    return [$res, $content];
}

sub process_content {
    my ($urow, $resp, $verbose) = @_;

    my ($res, $content) = @$resp;
    my ($user, $userid, $synurl, $lastmod, $etag, $readers) =
        map { $urow->{$_} } qw(user userid synurl lastmod etag numreaders);

    my $dbh = LJ::get_db_writer();

    # WARNING: blatant XML spec violation ahead...
    #
    # Blogger doesn't produce valid XML, since they don't handle encodings
    # correctly.  So if we see they have no encoding (which is UTF-8 implictly)
    # but it's not valid UTF-8, say it's Windows-1252, which won't
    # cause XML::Parser to barf... but there will probably be some bogus characters.
    # better than nothing I guess.  (personally, I'd prefer to leave it broken
    # and have people bitch at Blogger, but jwz wouldn't stop bugging me)
    # XML::Parser doesn't include Windows-1252, but we put it in cgi-bin/XML/* for it
    # to find.
    my $encoding;
    if ($content =~ /<\?xml.+?>/ && $& =~ /encoding=([\"\'])(.+?)\1/) {
        $encoding = lc($2);
    }
    if (! $encoding && ! LJ::is_utf8($content)) {
        $content =~ s/\?>/ encoding='windows-1252' \?>/;
    }

    # WARNING: another hack...
    # People produce what they think is iso-8859-1, but they include
    # Windows-style smart quotes.  Check for invalid iso-8859-1 and correct.
    if ($encoding =~ /^iso-8859-1$/i && $content =~ /[\x80-\x9F]/) {
        # They claimed they were iso-8859-1, but they are lying.
        # Assume it was Windows-1252.
        print "Invalid ISO-8859-1; assuming Windows-1252...\n" if $verbose;
        $content =~ s/encoding=([\"\'])(.+?)\1/encoding='windows-1252'/;
    }

    # parsing time...
    my ($feed, $error) = LJ::ParseFeed::parse_feed($content);
    if ($error) {
        # parse error!
        print "Parse error! $error\n" if $verbose;
        delay($userid, 3*60, "parseerror");
        $error =~ s! at /.*!!;
        $error =~ s/^\n//; # cleanup of newline at the beggining of the line
        LJ::set_userprop($userid, "rssparseerror", $error);
        return;
    }

    # another sanity check
    unless (ref $feed->{'items'} eq "ARRAY") {
        return delay($userid, 3*60, "noitems");
    }

    my @items = reverse @{$feed->{'items'}};

    # take most recent 20
    splice(@items, 0, @items-20) if @items > 20;

    # delete existing items older than the age which can show on a
    # friends view.
    my $su = LJ::load_userid($userid);
    my $udbh = LJ::get_cluster_master($su);
    unless ($udbh) {
        return delay($userid, 15, "nodb");
    }

    # TAG:LOG2:synsuck_delete_olderitems
    my $secs = ($LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14)+0;  # 2 week default.
    my $sth = $udbh->prepare("SELECT jitemid, anum FROM log2 WHERE journalid=? AND ".
                             "logtime < DATE_SUB(NOW(), INTERVAL $secs SECOND)");
    $sth->execute($userid);
    die $udbh->errstr if $udbh->err;
    while (my ($jitemid, $anum) = $sth->fetchrow_array) {
        print "DELETE itemid: $jitemid, anum: $anum... \n" if $verbose;
        if (LJ::delete_entry($su, $jitemid, 0, $anum)) {
            print "success.\n" if $verbose;
        } else {
            print "fail.\n" if $verbose;
        }
    }

    # determine if link tags are good or not, where good means
    # "likely to be a unique per item".  some feeds have the same
    # <link> element for each item, which isn't good.
    # if we have unique ids, we don't compare link tags

    my ($compare_links, $have_ids) = 0;
    {
        my %link_seen;
        foreach my $it (@items) {
            $have_ids = 1 if $it->{'id'};
            next unless $it->{'link'};
            $link_seen{$it->{'link'}} = 1;
        }
        $compare_links = 1 if !$have_ids and $feed->{'type'} eq 'rss' and
            scalar(keys %link_seen) == scalar(@items);
    }

    # if we have unique links/ids, load them for syndicated
    # items we already have on the server.  then, if we have one
    # already later and see it's changed, we'll do an editevent
    # instead of a new post.
    my %existing_item = ();
    if ($have_ids || $compare_links) {
        my $p = $have_ids ? LJ::get_prop("log", "syn_id") :
            LJ::get_prop("log", "syn_link");
        my $sth = $udbh->prepare("SELECT jitemid, value FROM logprop2 WHERE ".
                                 "journalid=? AND propid=? LIMIT 1000");
        $sth->execute($su->{'userid'}, $p->{'id'});
        while (my ($itemid, $id) = $sth->fetchrow_array) {
            $existing_item{$id} = $itemid;
        }
    }

    # post these items
    my $newcount = 0;
    my $errorflag = 0;
    my $mindate;  # "yyyy-mm-dd hh:mm:ss";
    my $notedate = sub {
        my $date = shift;
        $mindate = $date if ! $mindate || $date lt $mindate;
    };

    foreach my $it (@items) {

        # remove the SvUTF8 flag.  it's still UTF-8, but
        # we don't want perl knowing that and fucking stuff up
        # for us behind our back in random places all over
        # http://zilla.livejournal.org/show_bug.cgi?id=1037
        foreach my $attr (qw(id subject text link)) {
            $it->{$attr} = pack('C*', unpack('C*', $it->{$attr}));
        }

        my $dig = LJ::md5_struct($it)->b64digest;
        my $prevadd = $dbh->selectrow_array("SELECT MAX(dateadd) FROM synitem WHERE ".
                                            "userid=? AND item=?", undef,
                                            $userid, $dig);
        if ($prevadd) {
            $notedate->($prevadd);
            next;
        }

        my $now_dateadd = $dbh->selectrow_array("SELECT NOW()");
        die "unexpected format" unless $now_dateadd =~ /^\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d$/;

        $dbh->do("INSERT INTO synitem (userid, item, dateadd) VALUES (?,?,?)",
                 undef, $userid, $dig, $now_dateadd);
        $notedate->($now_dateadd);

        $newcount++;
        print "[$$] $dig - $it->{'subject'}\n" if $verbose;
        $it->{'text'} =~ s/^\s+//;
        $it->{'text'} =~ s/\s+$//;

        my $htmllink;
        if (defined $it->{'link'}) {
            $htmllink = "<p class='ljsyndicationlink'>" .
                "<a href='$it->{'link'}'>$it->{'link'}</a></p>";
        }

        # Show the <guid> link if it's present and different than the
        # <link>.
        # [zilla: 267] Patch: Chaz Meyers <lj-zilla@thechaz.net>
        if ( defined $it->{'id'} && $it->{'id'} ne $it->{'link'}
             && $it->{'id'} =~ m!^http://! )
        {
            $htmllink .= "<p class='ljsyndicationlink'>" .
                "<a href='$it->{'id'}'>$it->{'id'}</a></p>";
        }

        # rewrite relative URLs to absolute URLs, but only invoke the HTML parser
        # if we see there's some image or link tag, to save us some work if it's
        # unnecessary (the common case)
        if ($it->{'text'} =~ /<(?:img|a)\b/i) {
            # TODO: support XML Base?  http://www.w3.org/TR/xmlbase/
            my $base_href = $it->{'link'} || $synurl;
            LJ::CleanHTML::resolve_relative_urls(\$it->{'text'}, $base_href);
        }

        # $own_time==1 means we took the time from the feed rather than localtime
        my ($own_time, $year, $mon, $day, $hour, $min);

        if ($it->{'time'} &&
            $it->{'time'} =~ m!^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)!) {
            $own_time = 1;
            ($year, $mon, $day, $hour, $min) = ($1,$2,$3,$4,$5);
        } else {
            $own_time = 0;
            my @now = localtime();
            ($year, $mon, $day, $hour, $min) =
                ($now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);
        }

        my $command = "postevent";
        my $req = {
            'username' => $user,
            'ver' => 1,
            'subject' => $it->{'subject'},
            'event' => "$htmllink$it->{'text'}",
            'year' => $year,
            'mon' => $mon,
            'day' => $day,
            'hour' => $hour,
            'min' => $min,
            'props' => {
                'syn_link' => $it->{'link'},
            },
        };
        $req->{'props'}->{'syn_id'} = $it->{'id'}
        if $it->{'id'};

        my $flags = {
            'nopassword' => 1,
        };

        # if the post contains html linebreaks, assume it's preformatted.
        if ($it->{'text'} =~ /<(?:p|br)\b/i) {
            $req->{'props'}->{'opt_preformatted'} = 1;
        }

        # do an editevent if we've seen this item before
        my $id = $have_ids ? $it->{'id'} : $it->{'link'};
        my $old_itemid = $existing_item{$id};
        if ($id && $old_itemid) {
            $newcount--; # cancel increment above
            $command = "editevent";
            $req->{'itemid'} = $old_itemid;

            # the editevent requires us to resend the date info, which
            # we have to go fetch first, in case the feed doesn't have it

            # TAG:LOG2:synsuck_fetch_itemdates
            unless($own_time) {
                my $origtime =
                    $udbh->selectrow_array("SELECT eventtime FROM log2 WHERE ".
                                           "journalid=? AND jitemid=?", undef,
                                           $su->{'userid'}, $old_itemid);
                $origtime =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)/;
                $req->{'year'} = $1;
                $req->{'mon'} = $2;
                $req->{'day'} = $3;
                $req->{'hour'} = $4;
                $req->{'min'} = $5;
            }
        }

        my $err;
        my $pres = LJ::Protocol::do_request($command, $req, \$err, $flags);
        unless ($pres && ! $err) {
            print "  Error: $err\n" if $verbose;
            $errorflag = 1;
        }
    }

    # delete some unneeded synitems.  the limit 1000 is because
    # historically we never deleted and there are accounts with
    # 222,000 items on a myisam table, and that'd be quite the
    # delete hit.
    # the 14 day interval is because if a remote site deleted an
    # entry, it's possible for the oldest item that was previously
    # gone to reappear, and we want to protect against that a
    # little.
    unless ($LJ::DEBUG{'no_synitem_clean'}) {
        $dbh->do("DELETE FROM synitem WHERE userid=? AND ".
                 "dateadd < ? - INTERVAL 14 DAY LIMIT 1000",
                 undef, $userid, $mindate);
    }
    $dbh->do("UPDATE syndicated SET oldest_ourdate=? WHERE userid=?",
             undef, $mindate, $userid);

    # bail out if errors, and try again shortly
    if ($errorflag) {
        delay($userid, 30, "posterror");
        return;
    }

    # update syndicated account's userinfo if necessary
    LJ::load_user_props($su, "url", "urlname");
    {
        my $title = $feed->{'title'};
        $title = $su->{'user'} unless LJ::is_utf8($title);
        $title =~ s/[\n\r]//g;
        if ($title && $title ne $su->{'name'}) {
            LJ::update_user($su, { name => $title });
              LJ::set_userprop($su, "urlname", $title);
          }

        my $link = $feed->{'link'};
        if ($link && $link ne $su->{'url'}) {
            LJ::set_userprop($su, "url", $link);
          }

        my $des = $feed->{'description'};
        if ($des) {
            my $bio;
            if ($su->{'has_bio'} eq "Y") {
                $bio = $udbh->selectrow_array("SELECT bio FROM userbio WHERE userid=?", undef,
                                              $su->{'userid'});
            }
            if ($bio ne $des && $bio !~ /\[LJ:KEEP\]/) {
                if ($des) {
                    $su->do("REPLACE INTO userbio (userid, bio) VALUES (?,?)", undef,
                            $su->{'userid'}, $des);
                } else {
                    $su->do("DELETE FROM userbio WHERE userid=?", undef, $su->{'userid'});
                }
                LJ::update_user($su, { has_bio => ($des ? "Y" : "N") });
                LJ::MemCache::delete([$su->{'userid'}, "bio:$su->{'userid'}"]);
            }
        }
    }

    my $r_lastmod = LJ::http_to_time($res->header('Last-Modified'));
    my $r_etag = $res->header('ETag');

    # decide when to poll next (in minutes).
    # FIXME: this is super lame.  (use hints in RSS file!)
    my $int = $newcount ? 30 : 60;
    my $status = $newcount ? "ok" : "nonew";
    my $updatenew = $newcount ? ", lastnew=NOW()" : "";

    # update reader count while we're changing things, but not
    # if feed is stale (minimize DB work for inactive things)
    if ($newcount || ! defined $readers) {
        $readers = $dbh->selectrow_array("SELECT COUNT(*) FROM friends WHERE ".
                                         "friendid=?", undef, $userid);
    }

    # if readers are gone, don't check for a whole day
    $int = 60*24 unless $readers;

    $dbh->do("UPDATE syndicated SET checknext=DATE_ADD(NOW(), INTERVAL $int MINUTE), ".
             "lastcheck=NOW(), lastmod=?, etag=?, laststatus=?, numreaders=? $updatenew ".
             "WHERE userid=$userid", undef, $r_lastmod, $r_etag, $status, $readers);
}

1;


# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
