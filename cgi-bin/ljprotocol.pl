#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/console.pl";

#### New interface (meta handler) ... other handlers should call into this.
package LJ::Protocol;

sub translate
{
    my ($u, $msg, $vars) = @_;
    LJ::Lang::load_user_lang($u);

    return LJ::Lang::get_text($u->{'lang'}, "protocol.$msg", undef, $vars);
}

sub error_message
{
    my $code = shift;
    my $des;
    if ($code =~ /^(\d\d\d):(.+)/) {
        ($code, $des) = ($1, $2);
    }
    my %e = (
             # User Errors
             "100" => "Invalid username",
             "101" => "Invalid password",
             "102" => "Can't use custom security on shared/community journals.",
             "103" => "Poll error",
             "104" => "Error adding one or more friends",
             "150" => "Can't post as non-user",
             "151" => "Banned from journal",
             "152" => "Can't make back-dated entries in non-personal journal.",
             "153" => "Incorrect time value",
             "154" => "Can't add a redirected account as a friend",

             # Client Errors
             "200" => "Missing required argument(s)",
             "201" => "Unknown method",
             "202" => "Too many arguments",
             "203" => "Invalid argument(s)",
             "204" => "Invalid metadata datatype",
             "205" => "Unknown metadata",
             "206" => "Invalid destination journal username.",
             "207" => "Protocol version mismatch",
             "208" => "Invalid text encoding",

             # Access Errors
             "300" => "Don't have access to shared/community journal",
             "301" => "Access of restricted feature",
             "302" => "Can't edit post from requested journal",
             "303" => "Can't edit post in community journal",
             "304" => "Can't delete post in this community journal",
             "305" => "Action forbidden; account is suspended.",
             "306" => "This journal is temporarily in read-only mode.  Try again in a couple minutes.",
             "307" => "Selected shared journal no longer exists.",

             # Limit errors
             "401" => "Your account type doesn't permit adding syndicated accounts as friends.",
             "402" => "Your IP address is temporarily banned for exceeding the login failure rate.",
             "403" => "This would push you over your syndication quota.",
             "404" => "Cannot post",

             # Server Errors
             "500" => "Internal server error",
             "501" => "Database error",
             "502" => "Database temporarily unavailable",
             );

    my $prefix = "";
    my $error = $e{$code} || "BUG: Unknown error code!";
    if ($code >= 200) { $prefix = "Client error: "; }
    if ($code >= 500) { $prefix = "Server error: "; }
    my $totalerror = "$prefix$error";
    $totalerror .= ": $des" if $des;
    return $totalerror;
}

# returns result, or undef on failure
sub do_request_without_db
{
    my ($method, $req, $err, $flags) = @_;
    my $dbs = LJ::get_dbs();
    return fail($err,500) unless $dbs;
    return do_request($dbs, $method, $req, $err, $flags);
}

sub do_request
{
    # get the request and response hash refs
    my ($dbs, $method, $req, $err, $flags) = @_;

    # if version isn't specified explicitly, it's version 0
    $req->{'ver'} = 0 unless defined $req->{'ver'};

    $flags ||= {};
    my @args = ($dbs, $req, $err, $flags);

    if ($method eq "login")            { return login(@args);            }
    if ($method eq "getfriendgroups")  { return getfriendgroups(@args);  }
    if ($method eq "getfriends")       { return getfriends(@args);       }
    if ($method eq "friendof")         { return friendof(@args);         }
    if ($method eq "checkfriends")     { return checkfriends(@args);     }
    if ($method eq "getdaycounts")     { return getdaycounts(@args);     }
    if ($method eq "postevent")        { return postevent(@args);        }
    if ($method eq "editevent")        { return editevent(@args);        }
    if ($method eq "syncitems")        { return syncitems(@args);        }
    if ($method eq "getevents")        { return getevents(@args);        }
    if ($method eq "editfriends")      { return editfriends(@args);      }
    if ($method eq "editfriendgroups") { return editfriendgroups(@args); }
    if ($method eq "consolecommand")   { return consolecommand(@args);   }

    return fail($err,201);
}

sub login
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);

    my $dbh = $dbs->{'dbh'};
    return fail($err,502) unless $dbh && $dbs->{'reader'};

    my $u = $flags->{'u'};
    my $res = {};
    my $ver = $req->{'ver'};

    ## check for version mismatches
    ## non-Unicode installations can't handle versions >=1

    return fail($err,207, "This installation does not support Unicode clients")
        if $ver>=1 and not $LJ::UNICODE;

    ## return a message to the client to be displayed (optional)
    login_message($dbs, $req, $res, $flags);
    LJ::text_out(\$res->{'message'}) if $ver>=1 and defined $res->{'message'};

    ## report what shared journals this user may post in
    $res->{'usejournals'} = list_usejournals($dbs, $u);

    ## return their friend groups
    $res->{'friendgroups'} = list_friendgroups($dbs, $u);
    if ($ver >= 1) {
        foreach (@{$res->{'friendgroups'}}) {
            LJ::text_out(\$_->{'name'});
        }
    }

    ## if they gave us a number of moods to get higher than, then return them
    if (defined $req->{'getmoods'}) {
        $res->{'moods'} = list_moods($dbs, $req->{'getmoods'});
        if ($ver >= 1) {
            # currently all moods are in English, but this might change
            foreach (@{$res->{'moods'}}) { LJ::text_out(\$_->{'name'}) }
        }
    }

    ### picture keywords, if they asked for them.
    if ($req->{'getpickws'}) {
        my $pickws = list_pickws($dbs, $u);
        $res->{'pickws'} = [ map { $_->[0] } @$pickws ];
        if ($req->{'getpickwurls'}) {
            if ($u->{'defaultpicid'}) {
                 $res->{'defaultpicurl'} = "$LJ::USERPIC_ROOT/$u->{'defaultpicid'}/$u->{'userid'}";
            }
            $res->{'pickwurls'} = [ map {
                "$LJ::USERPIC_ROOT/$_->[1]/$u->{'userid'}"
            } @$pickws ];
        }
        if ($ver >= 1) {
            # validate all text
            foreach(@{$res->{'pickws'}}) { LJ::text_out(\$_); }
            foreach(@{$res->{'pickwurls'}}) { LJ::text_out(\$_); }
            LJ::text_out(\$res->{'defaultpicurl'});
        }
    }

    ## return client menu tree, if requested
    if ($req->{'getmenus'}) {
        $res->{'menus'} = hash_menus($dbs, $u);
        if ($ver >= 1) {
            # validate all text, just in case, even though currently
            # it's all English
            foreach (@{$res->{'menus'}}) {
                LJ::text_out(\$_->{'text'});
                LJ::text_out(\$_->{'url'}); # should be redundant
            }
	}
    }

    ## tell some users they can hit the fast servers later.
    $res->{'fastserver'} = 1 if LJ::get_cap($u, "fastserver");

    ## user info
    $res->{'userid'} = $u->{'userid'};
    $res->{'fullname'} = $u->{'name'};
    LJ::text_out(\$res->{'fullname'}) if $ver >= 1;

    ## update or add to clientusage table
    if ($req->{'clientversion'} =~ /^\S+\/\S+$/)  {
        my $client = $req->{'clientversion'};

        return fail($err, 208, "Bad clientversion string")
            if $ver >= 1 and not LJ::text_in($client);

        my $qclient = $dbh->quote($client);
        my $cu_sql = "REPLACE INTO clientusage (userid, clientid, lastlogin) " .
            "SELECT $u->{'userid'}, clientid, NOW() FROM clients WHERE client=$qclient";
        my $sth = $dbh->prepare($cu_sql);
        $sth->execute;
        unless ($sth->rows) {
            # only way this can be 0 is if client doesn't exist in clients table, so
            # we need to add a new row there, to get a new clientid for this new client:
            $dbh->do("INSERT INTO clients (client) VALUES ($qclient)");
            # and now we can do the query from before and it should work:
            $sth = $dbh->prepare($cu_sql);
            $sth->execute;
        }
    }

    return $res;
}

sub getfriendgroups
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};
    my $res = {};
    $res->{'friendgroups'} = list_friendgroups($dbs, $u);
    if ($req->{'ver'} >= 1) {
        foreach (@{$res->{'friendgroups'}}) {
	    LJ::text_out(\$_->{'name'});
        }
    }
    return $res;
}

sub getfriends
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return fail($req,502) unless $dbs->{'reader'};
    my $u = $flags->{'u'};
    my $res = {};
    if ($req->{'includegroups'}) {
        $res->{'friendgroups'} = list_friendgroups($dbs, $u);
        if ($req->{'ver'} >= 1) {
            foreach (@{$res->{'friendgroups'}}) {
                LJ::text_out(\$_->{'name'});
            }
        }
    }
    if ($req->{'includefriendof'}) {
        $res->{'friendofs'} = list_friends($dbs, $u, {
            'limit' => $req->{'friendoflimit'},
            'friendof' => 1,
        });
        if ($req->{'ver'} >= 1) {
            foreach(@{$res->{'friendofs'}}) { LJ::text_out(\$_->{'fullname'}) };
        }
    }
    $res->{'friends'} = list_friends($dbs, $u, {
        'limit' => $req->{'friendlimit'},
        'includebdays' => $req->{'includebdays'},
    });
    if ($req->{'ver'} >= 1) {
        foreach(@{$res->{'friends'}}) { LJ::text_out(\$_->{'fullname'}) };
    }
    return $res;
}

sub friendof
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return fail($req,502) unless $dbs->{'reader'};
    my $u = $flags->{'u'};
    my $res = {};
    $res->{'friendofs'} = list_friends($dbs, $u, {
        'friendof' => 1,
        'limit' => $req->{'friendoflimit'},
    });
    if ($req->{'ver'} >= 1) {
        foreach(@{$res->{'friendofs'}}) { LJ::text_out(\$_->{'fullname'}) };
    }
    return $res;
}

sub checkfriends
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    my $u = $flags->{'u'};
    my $res = {};

    # return immediately if they can't use this mode
    unless (LJ::get_cap($u, "checkfriends")) {
        $res->{'new'} = 0;
        $res->{'interval'} = 36000;  # tell client to bugger off
        return $res;
    }

    my $dbr = $dbs->{'reader'};
    my ($lastdate, $sth);

    ## have a valid date?
    my $lastupdate = $req->{'lastupdate'};
    if ($lastupdate) {
        return fail($err,203) unless
            ($lastupdate =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
        $lastupdate = "0000-00-00 00:00:00";
    }

    my $interval = LJ::get_cap_min($u, "checkfriends_interval");
    $res->{'interval'} = $interval;

    unless ($dbr) {
        # rather than return a 502 no-db error, just say no updates,
        # because problem'll be fixed soon enough by db admins
        $res->{'new'} = 0;
        $res->{'lastupdate'} = $lastupdate;
        return $res;
    }

    my $sql = "SELECT MAX(u.timeupdate) FROM userusage u, friends f ".
              "WHERE u.userid=f.friendid AND f.userid=$u->{'userid'}";
    if ($req->{'mask'} and $req->{'mask'} !~ /\D/) {
        $sql .= " AND f.groupmask & $req->{mask} > 0";
    }

    $sth = $dbr->prepare($sql);
    $sth->execute;
    my ($update) = $sth->fetchrow_array;
    $update ||= "0000-00-00 00:00:00";

    if ($req->{'lastupdate'} && $update gt $lastupdate) {
        $res->{'new'} = 1;
    } else {
        $res->{'new'} = 0;
    }

    $res->{'lastupdate'} = $update;

    return $res;
}

sub getdaycounts
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;
    my $ownerid = $flags->{'ownerid'};

    my $res = {};
    my ($db, $table, $ownercol) = ($dbs->{'reader'}, "log", "ownerid");
    if ($uowner->{'clusterid'}) {
        $db = LJ::get_cluster_reader($uowner);
        ($table, $ownercol) = ("log2", "journalid");
    }
    return fail($err,502) unless $db;

    my $sth = $db->prepare("SELECT year, month, day, COUNT(*) AS 'count' ".
                           "FROM $table WHERE $ownercol=$ownerid GROUP BY 1, 2, 3");
    $sth->execute;
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        my $date = sprintf("%04d-%02d-%02d", $y, $m, $d);
        push @{$res->{'daycounts'}}, { 'date' => $date, 'count' => $c };
    }
    return $res;
}

sub common_event_validation
{
    my ($dbs, $req, $err, $flags) = @_;
    my $dbr = $dbs->{'reader'};

    # date validation
    if ($req->{'year'} !~ /^\d\d\d\d$/ ||
        $req->{'year'} < 1970 ||    # before unix time started = bad
        $req->{'year'} > 2037)      # after unix time ends = worse!  :)
    {
        return fail($err,203,"Invalid year value.");
    }
    if ($req->{'mon'} !~ /^\d{1,2}$/ ||
        $req->{'mon'} < 1 ||
        $req->{'mon'} > 12)
    {
        return fail($err,203,"Invalid month value.");
    }
    if ($req->{'day'} !~ /^\d{1,2}$/ || $req->{'day'} < 1 ||
        $req->{'day'} > LJ::days_in_month($req->{'month'},
                                          $req->{'year'}))
    {
        return fail($err,203,"Invalid day of month value.");
    }
    if ($req->{'hour'} !~ /^\d{1,2}$/ ||
        $req->{'hour'} < 0 || $req->{'hour'} > 23)
    {
        return fail($err,203,"Invalid hour value.");
    }
    if ($req->{'min'} !~ /^\d{1,2}$/ ||
        $req->{'min'} < 0 || $req->{'min'} > 59)
    {
        return fail($err,203,"Invalid minute value.");
    }

    # column width
    # we only trim Unicode data

    if ($req->{'ver'} >=1 ) {
        $req->{'subject'} = LJ::text_trim($req->{'subject'}, LJ::BMAX_SUBJECT, LJ::CMAX_SUBJECT);
        $req->{'event'} = LJ::text_trim($req->{'event'}, LJ::BMAX_EVENT, LJ::CMAX_EVENT);
        foreach (keys %{$req->{'props'}}) {
            $req->{'props'}->{$_} = LJ::text_trim($req->{'props'}->{$_}, LJ::BMAX_PROP, LJ::CMAX_PROP);
        }
    }

    # setup non-user meta-data.  it's important we define this here to
    # 0.  if it's not defined at all, then an editevent where a user
    # removes random 8bit data won't remove the metadata.  not that
    # that matters much.  but having this here won't hurt.  false
    # meta-data isn't saved anyway.  so the only point of this next
    # line is making the metadata be deleted on edit.
    $req->{'props'}->{'unknown8bit'} = 0;

    # non-ASCII?
    unless ( LJ::is_ascii($req->{'event'}) && 
        LJ::is_ascii($req->{'subject'}) &&
        LJ::is_ascii(join(' ', values %{$req->{'props'}}) ))
    {
        if ($req->{'ver'} < 1) { # client doesn't support Unicode
            return fail($err,207,"only pure ASCII text is allowed for old clients; please upgrade your client") if $LJ::UNICODE_REQUIRE;

            # so rest of site can change chars to ? marks until
            # default user's encoding is set.  (legacy support)
            $req->{'props'}->{'unknown8bit'} = 1;
        } else {
            return fail($err,207, "This installation does not support Unicode clients") unless $LJ::UNICODE;
            # validate that the text is valid UTF-8
            if (!LJ::text_in($req->{'subject'}) ||
                !LJ::text_in($req->{'event'}) ||
                grep { !LJ::text_in($_) } values %{$req->{'props'}}) {
                return fail($err, 208, "The text entered is not a valid UTF-8 stream");
            }
        }
    }

    ## handle meta-data (properties)
    LJ::load_props($dbs, "log");
    foreach my $pname (keys %{$req->{'props'}})
    {
        my $p = LJ::get_prop("log", $pname);

        # does the property even exist?
        unless ($p) {
            $pname =~ s/[^\w]//g;
            return fail($err,205,$pname);
        }

        # don't validate its type if it's 0 or undef (deleting)
        next unless ($req->{'props'}->{$pname});

        my $ptype = $p->{'datatype'};
        my $val = $req->{'props'}->{$pname};

        if ($ptype eq "bool" && $val !~ /^[01]$/) {
            return fail($err,204,"Property \"$pname\" should be 0 or 1");
        }
        if ($ptype eq "num" && $val =~ /[^\d]/) {
            return fail($err,204,"Property \"$pname\" should be numeric");
        }
    }

    return 1;
}

sub postevent
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $ownerid = $flags->{'ownerid'};
    my $uowner = $flags->{'u_owner'} || $u;
    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};

    return fail($err,306) unless $dbh;
    return fail($err,200) unless ($req->{'event'} =~ /\S/);

    ### make sure community, shared, or news journals don't post
    ### note: shared and news journals are deprecated.  every shared journal
    ##        should one day be a community journal, of some form.
    return fail($err,150) if ($u->{'journaltype'} eq "C" ||
                              $u->{'journaltype'} eq "S" ||
                              $u->{'journaltype'} eq "N");

    # suspended users can't post
    return fail($err,305) if ($u->{'statusvis'} eq "S");

    # check the journal's read-only bit
    return fail($err,306) if LJ::get_cap($uowner, "readonly");

    # is the user allowed to post?
    return fail($err,404,$LJ::MSG_NO_POST) unless LJ::get_cap($u, "can_post");

    # can't post to deleted/suspended community
    return fail($err,307) unless $uowner->{'statusvis'} eq "V";
    
    #### clean up the event text
    my $event = $req->{'event'};

    # remove surrounding whitespace
    $event =~ s/^\s+//;
    $event =~ s/\s+$//;

    # convert line endings to unix format
    if ($req->{'lineendings'} eq "mac") {
        $event =~ s/\r/\n/g;
    } else {
        $event =~ s/\r//g;
    }

    return undef
        unless common_event_validation($dbs, $req, $err, $flags);

    ### allow for posting to journals that aren't yours (if you have permission)
    my $posterid = $u->{'userid'};

    # make the proper date format
    my $eventtime = sprintf("%04d-%02d-%02d %02d:%02d",
                                $req->{'year'}, $req->{'mon'},
                                $req->{'day'}, $req->{'hour'},
                                $req->{'min'});
    my $qeventtime = $dbh->quote($eventtime);

    # are they trying to post back in time?
    LJ::load_user_props($dbs, $u, "newesteventtime");
    if ($posterid == $ownerid && $u->{'newesteventtime'} && 
        $eventtime lt $u->{'newesteventtime'} &&!$req->{'props'}->{'opt_backdated'}) {
        return fail($err, 153, "Your most recent journal entry is dated $u->{'newesteventtime'}, but you're trying to post one at $eventtime without the backdate option turned on.  Please check your computer's clock.  Or, if you really mean to post in the past, use the backdate option.");
    }

    my $qsubject = $dbh->quote($req->{'subject'});
    my $qallowmask = $req->{'allowmask'}+0;
    my $security = "public";
    my $uselogsec = 0;
    if ($req->{'security'} eq "usemask" || $req->{'security'} eq "private") {
        $security = $req->{'security'};
    }
    if ($req->{'security'} eq "usemask") {
        $uselogsec = 1;
    }

    ## if newpost_minsecurity is set, new entries have to be 
    ## a minimum security level
    LJ::load_user_props($dbs, $uowner, "newpost_minsecurity");
    $security = "private" 
        if $uowner->{'newpost_minsecurity'} eq "private";
    ($security, $qallowmask) = ("usemask", 1)
        if $uowner->{'newpost_minsecurity'} eq "friends" 
        and $security eq "public";

    my $qsecurity = $dbh->quote($security);
    
    ### make sure user can't post with "custom security" on shared journals
    return fail($err,102)
        if ($req->{'security'} eq "usemask" &&
            $qallowmask != 1 && ($ownerid != $posterid));

    ### do processing of embedded polls
    my @polls = ();
    if (LJ::Poll::contains_new_poll(\$event))
    {
        return fail($err,301,"Your account type doesn't permit creating polls.")
            unless (LJ::get_cap($u, "makepoll")
                    || ($uowner->{'journaltype'} eq "C"
                        && LJ::get_cap($uowner, "makepoll")
                        && LJ::check_priv($dbs, $u, "sharedjournal", $uowner->{'user'})));

        my $error = "";
        @polls = LJ::Poll::parse($dbs, \$event, \$error, {
            'journalid' => $ownerid,
            'posterid' => $posterid,
        });
        return fail($err,103,$error) if $error;
    }

    # make sure this user isn't banned from posting here (if
    # this is a community journal)
    return fail($err,151) if
        LJ::is_banned($dbs, $posterid, $ownerid);

    # don't allow backdated posts in communities
    return fail($err,152) if
        ($req->{'props'}->{"opt_backdated"} &&
         $uowner->{'journaltype'} ne "P");

    my $qownerid = $ownerid+0;
    my $qposterid = $posterid+0;

    # by default we record the true reverse time that the item was entered.
    # however, if backdate is on, we put the reverse time at the end of time
    # (which makes it equivalent to 1969, but get_recent_items will never load
    # it... where clause there is: < $LJ::EndOfTime).  but this way we can
    # have entries that don't show up on friends view, now that we don't have
    # the hints table to not insert into.
    my $rlogtime = "$LJ::EndOfTime";
    unless ($req->{'props'}->{"opt_backdated"}) {
        $rlogtime .= "-UNIX_TIMESTAMP(?)";
    }

    my $dbcm = $dbh;
    my $clustered = 0;
    my $anum  = int(rand(256));
    my $udbh_now;  # current time on the master user db

    if ($uowner->{'clusterid'}) {
        $dbcm = LJ::get_cluster_master($uowner);
        $clustered = 1;

        return fail($err,306) unless $dbcm;

        # before we get going here, we want to make sure to purge this user's
        # delitem cmd buffer, otherwise we could have a race and that might
        # wake up later and delete this item which is replacing in the database
        # the old last item which is marked for deletion:
        LJ::cmd_buffer_flush($dbh, $dbcm, "delitem", $ownerid);

        $udbh_now = $dbcm->selectrow_array("SELECT NOW()");
        $rlogtime =~ s/\?/\'$udbh_now\'/;  # replace parameter above with current time

        $dbcm->do("INSERT INTO log2 (journalid, posterid, eventtime, logtime, security, ".
                  "allowmask, replycount, year, month, day, revttime, rlogtime, anum) ".
                  "VALUES ($qownerid, $qposterid, $qeventtime, '$udbh_now', $qsecurity, $qallowmask, ".
                  "0, $req->{'year'}, $req->{'mon'}, $req->{'day'}, $LJ::EndOfTime-".
                  "UNIX_TIMESTAMP($qeventtime), $rlogtime, $anum)");
    } else {
        $rlogtime =~ s/\?//;  # kill the parameter, which we don't use in this case.
        $dbcm->do("INSERT INTO log (ownerid, posterid, eventtime, logtime, security, ".
                  "allowmask, replycount, year, month, day, revttime, rlogtime) ".
                  "VALUES ($qownerid, $qposterid, $qeventtime, NOW(), $qsecurity, $qallowmask, ".
                  "0, $req->{'year'}, $req->{'mon'}, $req->{'day'}, $LJ::EndOfTime-".
                  "UNIX_TIMESTAMP($qeventtime), $rlogtime)");
    }
    return fail($err,501,$dbcm->errstr) if $dbcm->err;

    my $itemid = $dbcm->{'mysql_insertid'};
    return fail($err,501,"No itemid could be generated.") unless $itemid;

    my $ditemid = $clustered ? ($itemid * 256 + $anum) : $itemid;

    ### finish embedding stuff now that we have the itemid
    {
        ### this should NOT return an error, and we're mildly fucked by now
        ### if it does (would have to delete the log row up there), so we're
        ### not going to check it for now.

        my $error = "";
        LJ::Poll::register($dbs, \$event, \$error, $ditemid, @polls);
    }
    #### /embedding

    ### extract links for meme tracking
    unless ($req->{'security'} eq "usemask" ||
            $req->{'security'} eq "private")
    {
        foreach my $url (LJ::get_urls($event)) {
            my $jid = $clustered ? $ownerid : 0;
            LJ::record_meme($dbs, $url, $posterid, $ditemid, $jid);
        }
    }

    # record the eventtime of the last update (for own journals only)
    LJ::set_userprop($dbs, $posterid, 'newesteventtime', $eventtime)
        if $posterid == $ownerid and not $req->{'props'}->{'opt_backdated'};

    # record journal's disk usage (clustered users only)
    if ($clustered)
    {
        my $bytes = length($event) + length($req->{'subject'});
        LJ::dudata_set($dbcm, $ownerid, 'L', $itemid, $bytes);
    }

    my $qevent = $dbh->quote($event);
    $event = "";

    if ($clustered) {
        $dbcm->do("REPLACE INTO logtext2 (journalid, jitemid, subject, event) ".
                  "VALUES ($ownerid, $itemid, $qsubject, $qevent)");
        if ($dbcm->err) {
            my $msg = $dbcm->errstr;
            LJ::delete_item2($dbh, $dbcm, $ownerid, $itemid);   # roll-back
            return fail($err,501,"logtext:$msg");
        }
    } else {
        my @prefix = ("");
        if ($LJ::USE_RECENT_TABLES) { push @prefix, "recent_"; }
        foreach my $pfx (@prefix)
        {
            $dbh->do("INSERT INTO ${pfx}logtext (itemid, subject, event) ".
                     "VALUES ($itemid, $qsubject, $qevent)");
            if ($dbh->err) {
                my $msg = $dbh->errstr;
                LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
                return fail($err,501,$msg);
            }
        }
    }

    # this is to speed month view and other places that don't need full text.
    if ($clustered) {
        $dbcm->do("REPLACE INTO logsubject2 (journalid, jitemid, subject) ".
                  "VALUES ($ownerid, $itemid, $qsubject)");
        if ($dbcm->err) {
            my $msg = $dbcm->errstr;
            LJ::delete_item2($dbh, $dbcm, $ownerid, $itemid);   # roll-back
            return fail($err,501,"logsubject:$msg");
        }
    } else {
        $dbh->do("INSERT INTO logsubject (itemid, subject) VALUES ($itemid, $qsubject)");
        if ($dbh->err) {
            my $msg = $dbh->errstr;
            LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
            return fail($err,501,$msg);
        }
    }

    ## update sync table (selected from log table, so logtime is identical!)
    if ($clustered) {
        $dbcm->do("REPLACE INTO syncupdates2 (userid, atime, nodetype, nodeid, atype) ".
                  "VALUES ($ownerid, '$udbh_now', 'L', $itemid, 'create')");
        if ($dbcm->err) {
            my $msg = $dbcm->errstr;
            LJ::delete_item2($dbh, $dbcm, $ownerid, $itemid);   # roll-back
            return fail($err,501,$msg);
        }
    } else {
        $dbh->do("REPLACE INTO syncupdates (userid, atime, nodetype, nodeid, atype) ".
                 "SELECT ownerid, logtime, 'L', itemid, 'create' FROM log WHERE itemid=$itemid");
        if ($dbh->err) {
            my $msg = $dbh->errstr;
            LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
            return fail($err,501,$msg);
        }
    }

    # keep track of custom security stuff in other table.
    if ($uselogsec) {
        if ($clustered) {
            $dbcm->do("REPLACE INTO logsec2 (journalid, jitemid, allowmask) ".
                      "VALUES ($qownerid, $itemid, $qallowmask)");
            if ($dbcm->err) {
                my $msg = $dbcm->errstr;
                LJ::delete_item2($dbh, $dbcm, $ownerid, $itemid);   # roll-back
                return fail($err,501,"logsec2:$msg");
            }
        } else {
            $dbh->do("INSERT INTO logsec (ownerid, itemid, allowmask) ".
                     "VALUES ($qownerid, $itemid, $qallowmask)");
            if ($dbh->err) {
                my $msg = $dbh->errstr;
                LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
                return fail($err,501,$msg);
            }
        }
    }

    # meta-data
    if (%{$req->{'props'}}) {
        my $propinsert = "";
        foreach my $pname (keys %{$req->{'props'}}) {
            next unless $req->{'props'}->{$pname};
            if ($propinsert) {
                $propinsert .= ", ";
            } else {
                if ($clustered) {
                    $propinsert = "REPLACE INTO logprop2 (journalid, jitemid, propid, value) VALUES ";
                } else {
                    $propinsert = "INSERT INTO logprop (itemid, propid, value) VALUES ";
                }
            }
            my $p = LJ::get_prop("log", $pname);
            if ($p && $pname ne "revnum") {
                my $qvalue = $dbh->quote($req->{'props'}->{$pname});
                if ($clustered) {
                    $propinsert .= "($ownerid, $itemid, $p->{'id'}, $qvalue)";
                } else {
                    $propinsert .= "($itemid, $p->{'id'}, $qvalue)";
                }
            }
        }
        if ($propinsert) {
            $dbcm->do($propinsert);   # note: $dbcm may be $dbh
            if ($dbcm->err) {
                my $msg = $dbh->errstr;
                if ($clustered) {
                    LJ::delete_item2($dbh, $dbcm, $ownerid, $itemid);   # roll-back
                } else {
                    LJ::delete_item($dbh, $ownerid, $itemid);   # roll-back
                }
                return fail($err,501,"logprop2:$msg");
            }
        }
    }

    $dbh->do("UPDATE userusage SET timeupdate=NOW(), lastitemid=$itemid ".
             "WHERE userid=$qownerid");

    # update user update table (on which friends views rely)
    {
        my @bits;
        if ($security eq "public") {
            push @bits, 31;  # 31 means public
        } elsif ($security eq "private") {
            push @bits, 32;  # 1<<32 doesn't exist (too big), but we'll use it in this table
        } else {
            for (my $i=0; $i<=30; $i++) {
                next unless $qallowmask & (1<<$i);
                push @bits, $i;
            }
        }
        if (@bits) {
            $dbh->do("REPLACE INTO userupdate (userid, groupbit, timeupdate) VALUES ".
                     join(",", map { "($ownerid, $_, NOW())" } @bits));
        }
    }

    my $res = {};
    $res->{'itemid'} = $itemid;  # by request of mart
    $res->{'anum'} = $anum if $clustered;
    return $res;
}

sub editevent
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);

    # we check later that user owns entry they're modifying, so all
    # we care about for check_altusage is that the target journal
    # exists, and we want it to setup some data in $flags.
    $flags->{'ignorecanuse'} = 1;
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $ownerid = $flags->{'ownerid'};
    my $uowner = $flags->{'u_owner'} || $u;
    my $posterid = $u->{'userid'};
    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};
    my $sth;

    my $qitemid = $req->{'itemid'}+0;

    # check the journal's read-only bit
    return fail($err,306) if LJ::get_cap($uowner, "readonly");

    # can't edit in deleted/suspended community
    return fail($err,307) unless $uowner->{'statusvis'} eq "V";

    my ($dbcm, $dbcr, $clustered) = ($dbh, $dbr, 0);
    if ($uowner->{'clusterid'}) {
        $dbcm = LJ::get_cluster_master($uowner);
        $clustered = 1;
    }
    return fail($err,306) unless $dbcm;

    # fetch the old entry from master database so we know what we
    # really have to update later.  usually people just edit one part,
    # not every field in every table.  reads are quicker than writes,
    # so this is worth it.
    my $oldevent;
    if ($clustered)
    {
        $oldevent = $dbcm->selectrow_hashref
            ("SELECT l.journalid AS 'ownerid', l.posterid, l.eventtime, l.logtime, ".
             "l.compressed, l.security, l.allowmask, l.year, l.month, l.day, lt.subject, ".
             "MD5(lt.event) AS 'md5event', l.rlogtime, l.anum FROM log2 l, logtext2 lt ".
             "WHERE l.journalid=$ownerid AND lt.journalid=$ownerid ".
             "AND l.jitemid=$qitemid AND lt.jitemid=$qitemid");

	# a few times, logtext2 has been empty, with log2 existing,
	# and then the post is undeletable since the join matches
	# nothing.  this is a ugly hack work-around, but without using
	# transactions to guarantee we never bomb out between log2 and
	# logtext2 insertion, this is the price we way.
	unless ($oldevent) {
	    $oldevent = $dbcm->selectrow_hashref
		("SELECT l.journalid AS 'ownerid', l.posterid, l.eventtime, l.logtime, ".
		 "l.compressed, l.security, l.allowmask, l.year, l.month, l.day, ".
		 "l.rlogtime, l.anum FROM log2 l WHERE l.journalid=$ownerid AND l.jitemid=$qitemid");
	}

    } else {
        $oldevent = $dbcm->selectrow_hashref
            ("SELECT l.ownerid, l.posterid, l.eventtime, l.logtime, ".
             "l.compressed, l.security, l.allowmask, l.year, l.month, l.day, lt.subject, ".
             "MD5(lt.event) AS 'md5event', l.rlogtime FROM log l, logtext lt ".
             "WHERE l.itemid=$qitemid AND lt.itemid=$qitemid");
    }

    # kill seconds in eventtime, since we don't use it, then we can use 'eq' and such
    $oldevent->{'eventtime'} =~ s/:00$//;

    ### make sure this user is allowed to edit this entry
    return fail($err,302)
        unless ($ownerid == $oldevent->{'ownerid'});

    ### what can they do to somebody elses entry?  (in shared journal)
    if ($posterid != $oldevent->{'posterid'})
    {
        ## deleting.
        return fail($err,304)
            if ($req->{'event'} !~ /\S/ && !
                ($ownerid == $u->{'userid'} ||
                 # community account can delete it (ick)

                 LJ::check_priv($dbr, $u,
                                "sharedjournal", $req->{'usejournal'})
                 # if user is a community maintainer they can delete
                 # it too (good)
                 ));

        ## editing:
        return fail($err,303)
            if ($req->{'event'} =~ /\S/);
    }

    ## update sync table (before we actually do it!  in case updates
    ## partially fail below)
    if ($clustered) {
        my $synctype = "update";
        if ($req->{'event'} !~ /\S/) { $synctype = "del"; }
        $dbcm->do("REPLACE INTO syncupdates2 (userid, atime, nodetype, nodeid, atype) ".
                  "VALUES ($ownerid, NOW(), 'L', $qitemid, '$synctype')");
    } else {
        $dbh->do("REPLACE INTO syncupdates (userid, atime, nodetype, nodeid, atype) ".
                 "VALUES ($ownerid, NOW(), 'L', $qitemid, 'update')");
    }

    # simple logic for deleting an entry
    if ($req->{'event'} !~ /\S/)
    {
        # if their newesteventtime prop equals the time of the one they're deleting
        # then delete their newesteventtime.
        if ($u->{'userid'} == $uowner->{'userid'}) {
            LJ::load_user_props($dbs, $u, "newesteventtime");
            if ($u->{'newesteventtime'} eq $oldevent->{'eventtime'}) {
                LJ::set_userprop($dbs, $u, "newesteventtime", undef);
            }
        }

        if ($clustered) {
            LJ::delete_item2($dbh, $dbcm, $ownerid, $req->{'itemid'},
                             'quick', $oldevent->{'anum'});
        } else {
            LJ::delete_item($dbh, $ownerid, $req->{'itemid'});
        }
        my $res = { 'itemid' => $qitemid,
                    'anum' => $oldevent->{'anum'} };
        return $res;
    }

    # don't allow backdated posts in communities
    return fail($err,152) if
        ($req->{'props'}->{"opt_backdated"} &&
         $uowner->{'journaltype'} ne "P");

    # updating an entry:
    return undef
        unless common_event_validation($dbs, $req, $err, $flags);

    ### load existing meta-data
    my %curprops;

    if ($clustered) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($dbcm, $ownerid, [ $qitemid ], \%curprops);
    } else {
        LJ::load_log_props($dbh, [ $qitemid ], \%curprops);
    }

    ## handle meta-data (properties)
    my %props_byname = ();
    foreach my $key (keys %{$req->{'props'}}) {
        ## changing to something else?
        if ($curprops{$qitemid}->{$key} ne $req->{'props'}->{$key}) {
            $props_byname{$key} = $req->{'props'}->{$key};
        }
    }

    #### clean up the event text
    my $event = $req->{'event'};

    # remove surrounding whitespace
    $event =~ s/^\s+//;
    $event =~ s/\s+$//;

    # convert line endings to unix format
    if ($req->{'lineendings'} eq "mac") {
        $event =~ s/\r/\n/g;
    } else {
        $event =~ s/\r//g;
    }
    my $qevent = $dbh->quote($event);
    my $bytes = length($event) + length($req->{'subject'});
    $event = "";

    my $eventtime = sprintf("%04d-%02d-%02d %02d:%02d",
                            map { $req->{$_} } qw(year mon day hour min));
    my $qeventtime = $dbh->quote($eventtime);

    my $qallowmask = $req->{'allowmask'}+0;
    my $security = "public";
    if ($req->{'security'} eq "private" || $req->{'security'} eq "usemask") {
        $security = $req->{'security'};
    }

    my $qyear = $req->{'year'}+0;
    my $qmonth = $req->{'mon'}+0;
    my $qday = $req->{'day'}+0;

    if ($eventtime ne $oldevent->{'eventtime'} ||
        $security ne $oldevent->{'security'} ||
        $qallowmask != $oldevent->{'allowmask'})
    {
        # are they changing their most recent post?
        if ($eventtime ne $oldevent->{'eventtime'} &&
            $u->{'userid'} == $uowner->{'userid'}) 
        {
            LJ::load_user_props($dbs, $u, "newesteventtime");
            if ($u->{'newesteventtime'} eq $oldevent->{'eventtime'}) {
                LJ::set_userprop($dbs, $u, "newesteventtime", $eventtime);
            }
        }
        
        my $qsecurity = $dbh->quote($security);
        if ($clustered) {
            $dbcm->do("UPDATE log2 SET eventtime=$qeventtime, revttime=$LJ::EndOfTime-".
                      "UNIX_TIMESTAMP($qeventtime), year=$qyear, month=$qmonth, day=$qday, ".
                      "security=$qsecurity, allowmask=$qallowmask WHERE journalid=$ownerid ".
                      "AND jitemid=$qitemid");
        } else {
            $dbh->do("UPDATE log SET eventtime=$qeventtime, revttime=$LJ::EndOfTime-".
                     "UNIX_TIMESTAMP($qeventtime), year=$qyear, month=$qmonth, day=$qday, ".
                     "security=$qsecurity, allowmask=$qallowmask WHERE itemid=$qitemid");
        }
    }

    if ($security ne $oldevent->{'security'} ||
        $qallowmask != $oldevent->{'allowmask'})
    {
        if ($security eq "public" || $security eq "private") {
            if ($clustered) {
                $dbcm->do("DELETE FROM logsec2 WHERE journalid=$ownerid AND jitemid=$qitemid");
            } else {
                $dbh->do("DELETE FROM logsec WHERE ownerid=$ownerid AND itemid=$qitemid");
            }
        } else {
            my $qsecurity = $dbh->quote($security);
            if ($clustered) {
                $dbcm->do("REPLACE INTO logsec2 (journalid, jitemid, allowmask) ".
                          "VALUES ($ownerid, $qitemid, $qallowmask)");
            } else {
                $dbh->do("REPLACE INTO logsec (ownerid, itemid, allowmask) ".
                         "VALUES ($ownerid, $qitemid, $qallowmask)");
            }
        }
        return fail($err,501,$dbcm->errstr) if $dbcm->err;
    }

    if (Digest::MD5::md5_hex($event) ne $oldevent->{'md5event'} ||
        $req->{'subject'} ne $oldevent->{'subject'})
    {
        my $qsubject = $dbh->quote($req->{'subject'});

        if ($clustered) {
            $dbcm->do("UPDATE logtext2 SET event=$qevent, subject=$qsubject ".
                      "WHERE journalid=$ownerid AND jitemid=$qitemid");
        } else {
            my @prefix = ("");
            if ($LJ::USE_RECENT_TABLES) { push @prefix, "recent_"; }
            foreach my $pfx (@prefix) {
                $dbh->do("UPDATE ${pfx}logtext SET event=$qevent, subject=$qsubject ".
                         "WHERE itemid=$qitemid");
            }
            return fail($err,501,$dbcm->errstr) if $dbcm->err;
        }
        if ($clustered) {
            $dbcm->do("REPLACE INTO logsubject2 (journalid, jitemid, subject) ".
                      "VALUES ($ownerid, $qitemid, $qsubject)");
        } else {
            $dbh->do("REPLACE INTO logsubject (itemid, subject) ".
                     "VALUES ($qitemid, $qsubject)");
        }

        # update disk usage
        if ($clustered) {
            LJ::dudata_set($dbcm, $ownerid, 'L', $qitemid, $bytes);
        }

        return fail($err,501,$dbcm->errstr) if $dbcm->err;
    }

    # up the revision number
    $req->{'props'}->{'revnum'} = ($curprops{$qitemid}->{'revnum'} || 0) + 1;

    # handle the props
    {
        my $propinsert = "";
        my @props_to_delete;
        foreach my $pname (keys %{$req->{'props'}}) {
            my $p = LJ::get_prop("log", $pname);
            next unless $p;
            my $val = $req->{'props'}->{$pname};
            unless ($val) {
                push @props_to_delete, $p->{'id'};
                next;
            }
            if ($propinsert) {
                $propinsert .= ", ";
            } else {
                if ($clustered) {
                    $propinsert = "REPLACE INTO logprop2 (journalid, jitemid, propid, value) VALUES ";
                } else {
                    $propinsert = "REPLACE INTO logprop (itemid, propid, value) VALUES ";
                }
            }
            my $qvalue = $dbh->quote($val);
            if ($clustered) {
                $propinsert .= "($ownerid, $qitemid, $p->{'id'}, $qvalue)";
            } else {
                $propinsert .= "($qitemid, $p->{'id'}, $qvalue)";
            }
        }
        if ($propinsert) { $dbcm->do($propinsert); }
        if (@props_to_delete) {
            my $propid_in = join(", ", @props_to_delete);
            if ($clustered) {
                $dbcm->do("DELETE FROM logprop2 WHERE journalid=$ownerid AND ".
                          "jitemid=$qitemid AND propid IN ($propid_in)");
            } else {
                $dbh->do("DELETE FROM logprop WHERE itemid=$qitemid AND propid IN ($propid_in)");
            }
        }
    }

    # deal with backdated changes.  if the entry's rlogtime is
    # $EndOfTime, then it's backdated.  if they want that off, need to
    # reset rlogtime to real reverse log time.  also need to set
    # rlogtime to $EndOfTime if they're turning backdate on.
    if ($req->{'props'}->{'opt_backdated'} eq "1" &&
        $oldevent->{'rlogtime'} != $LJ::EndOfTime) {
        if ($clustered) {
            $dbcm->do("UPDATE log2 SET rlogtime=$LJ::EndOfTime WHERE ".
                      "journalid=$ownerid AND jitemid=$qitemid");
        } else {
            $dbh->do("UPDATE log SET rlogtime=$LJ::EndOfTime WHERE ".
                     "itemid=$qitemid");
        }
    }
    if ($req->{'props'}->{'opt_backdated'} eq "0" &&
        $oldevent->{'rlogtime'} == $LJ::EndOfTime) {
        if ($clustered) {
            $dbcm->do("UPDATE log2 SET rlogtime=$LJ::EndOfTime-UNIX_TIMESTAMP(logtime) ".
                      "WHERE journalid=$ownerid AND jitemid=$qitemid");
        } else {
            $dbh->do("UPDATE log SET rlogtime=$LJ::EndOfTime-UNIX_TIMESTAMP(logtime) ".
                     "WHERE itemid=$qitemid");
        }
    }

    return fail($err,501,$dbcm->errstr) if $dbcm->err;

    my $res = { 'itemid' => $qitemid };
    $res->{'anum'} = $oldevent->{'anum'} if defined $oldevent->{'anum'};
    return $res;
}

sub getevents
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $uowner = $flags->{'u_owner'} || $u;

    ### shared-journal support
    my $posterid = $u->{'userid'};
    my $ownerid = $flags->{'ownerid'};

    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};
    my $sth;

    my ($dbcr, $clustered) = ($dbr, 0);
    if ($uowner->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($uowner);
        $clustered = 1;
    }
    return fail($err,502) unless $dbcr;

    # can't pull events from deleted/suspended journal
    return fail($err,307) unless $uowner->{'statusvis'} eq "V";

    # if this is on, we sort things different (logtime vs. posttime)
    # to avoid timezone issues
    my $is_community = ($uowner->{'journaltype'} eq "C" ||
                        $uowner->{'journaltype'} eq "S");

    # in some cases we'll use the master, to ensure there's no
    # replication delay.  useful cases: getting one item, use master
    # since user might have just made a typo and realizes it as they
    # post, or wants to append something they forgot, etc, etc.  in
    # other cases, slave is pretty sure to have it.
    my $use_master = 0;

    # the benefit of this mode over actually doing 'lastn/1' is
    # the $use_master usage.
    if ($req->{'selecttype'} eq "one" && $req->{'itemid'} eq "-1") {
        $req->{'selecttype'} = "lastn";
        $req->{'howmany'} = 1;
        undef $req->{'itemid'};
        $use_master = 1;  # see note above.
    }

    # build the query to get log rows.  each selecttype branch is
    # responsible for either populating the following 3 variables
    # OR just populating $sql
    my ($orderby, $where, $limit);
    my $sql;
    if ($req->{'selecttype'} eq "day")
    {
        return fail($err,203)
            unless ($req->{'year'} =~ /^\d\d\d\d$/ &&
                    $req->{'month'} =~ /^\d\d?$/ &&
                    $req->{'day'} =~ /^\d\d?$/ &&
                    $req->{'month'} >= 1 && $req->{'month'} <= 12 &&
                    $req->{'day'} >= 1 && $req->{'day'} <= 31);

        my $qyear = $dbh->quote($req->{'year'});
        my $qmonth = $dbh->quote($req->{'month'});
        my $qday = $dbh->quote($req->{'day'});
        $where = "AND year=$qyear AND month=$qmonth AND day=$qday";
        $limit = "LIMIT 200";  # FIXME: unhardcode this constant (also in ljviews.pl)

        # see note above about why the sort order is different
        $orderby = $is_community ? "ORDER BY logtime" : "ORDER BY eventtime";
    }
    elsif ($req->{'selecttype'} eq "lastn")
    {
        my $howmany = $req->{'howmany'} || 20;
        if ($howmany > 50) { $howmany = 50; }
        $howmany = $howmany + 0;
        $limit = "LIMIT $howmany";

        # okay, follow me here... see how we add the revttime predicate
        # even if no beforedate key is present?  you're probably saying,
        # that's retarded -- you're saying: "revttime > 0", that's like
        # saying, "if entry occured at all."  yes yes, but that hints
        # mysql's braindead optimizer to use the right index.
        my $rtime_after = 0;
        my $rtime_what = $is_community ? "rlogtime" : "revttime";
        if ($req->{'beforedate'}) {
            return fail($err,203,"Invalid beforedate format.")
                unless ($req->{'beforedate'} =~
                        /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/);
            my $qd = $dbh->quote($req->{'beforedate'});
            $rtime_after = "$LJ::EndOfTime-UNIX_TIMESTAMP($qd)";
        }
        $where .= "AND $rtime_what > $rtime_after ";
        $orderby = "ORDER BY $rtime_what";
    }
    elsif ($req->{'selecttype'} eq "one")
    {
        my $id = $req->{'itemid'} + 0;
        $where = $clustered ? "AND jitemid=$id" : "AND itemid=$id";
    }
    elsif ($req->{'selecttype'} eq "syncitems")
    {
        my ($date);
        ## have a valid date?
        $date = $req->{'lastsync'} || "0000-00-00 00:00:00";
        if ($date !~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/) {
            return fail($err,203,"Invalid syncitems date format.");
        }

        my $LIMIT = 300;
        if ($clustered) {
            $sql = "SELECT jitemid, eventtime, security, allowmask, anum, posterid ".
                "FROM log2 l, syncupdates2 s ".
                "WHERE s.userid=$ownerid AND l.journalid=$ownerid ".
                "AND s.atime>='$date' AND s.nodetype='L' AND s.nodeid=l.jitemid ".
                "AND s.nodeid=l.jitemid ORDER BY s.atime LIMIT $LIMIT";
        } else {
            $use_master = 1;
            $sql = "SELECT itemid, eventtime, security, allowmask, posterid ".
                "FROM log l, syncupdates s WHERE s.userid=$ownerid ".
                "AND s.atime>='$date' AND s.nodetype='L' AND s.nodeid=l.itemid ".
                "AND s.nodeid=l.itemid ORDER BY s.atime LIMIT $LIMIT";
        }
    }
    else
    {
        return fail($err,200,"Invalid selecttype.");
    }

    # common SQL template:
    unless ($sql) {
        if ($clustered) {
            $sql = "SELECT jitemid, eventtime, security, allowmask, anum, posterid ".
                   "FROM log2 WHERE journalid=$ownerid $where $orderby $limit";
        } else {
            $sql = "SELECT itemid, eventtime, security, allowmask, posterid ".
                      "FROM log WHERE ownerid=$ownerid $where $orderby $limit";
        }
    }

    # whatever selecttype might have wanted us to use the master db.
    $dbcr = $clustered ? LJ::get_cluster_master($uowner) : $dbh
        if $use_master;

    return fail($err,502) unless $dbcr;

    ## load the log rows
    ($sth = $dbcr->prepare($sql))->execute;
    return fail($err,501,$dbcr->errstr) if $dbcr->err;

    my $count = 0;
    my @itemids = ();
    my $res = {};
    my $events = $res->{'events'} = [];
    my %evt_from_itemid;

    while (my ($itemid, $eventtime, $sec, $mask, $anum, $jposterid) = $sth->fetchrow_array)
    {
        $count++;
        my $evt = {};
        $evt->{'itemid'} = $itemid;
        push @itemids, $itemid;

        $evt_from_itemid{$itemid} = $evt;

        $evt->{"eventtime"} = $eventtime;
        if ($sec ne "public") {
            $evt->{'security'} = $sec;
            $evt->{'allowmask'} = $mask if $sec eq "usemask";
        }
        $evt->{'anum'} = $anum if $clustered;
        $evt->{'poster'} = LJ::get_username($dbs, $jposterid) if $jposterid != $ownerid;
        push @$events, $evt;
    }

    # load properties. Even if the caller doesn't want them, we need
    # them in Unicode installations to recognize older 8bit non-UF-8
    # entries.
    unless ($req->{'noprops'} && !$LJ::UNICODE) 
    {
	### do the properties now
	$count = 0;
	my %props = ();
	if ($clustered) {
            LJ::load_props($dbs, "log");
            LJ::load_log_props2($dbcr, $ownerid, \@itemids, \%props);
	} else {
            LJ::load_log_props($dbcr, \@itemids, \%props);
	}
	foreach my $itemid (keys %props) {
	    my $evt = $evt_from_itemid{$itemid};
	    $evt->{'props'} = {};
	    foreach my $name (keys %{$props{$itemid}}) {
		my $value = $props{$itemid}->{$name};
		$value =~ s/\n/ /g;
		$evt->{'props'}->{$name} = $value;
	    }
	}
    }

    ## load the text
    my $text;
    my $gt_opts = {
        'prefersubjects' => $req->{'prefersubject'} ,
        'usemaster' => $use_master,
    };
    if ($clustered) {
        $text = LJ::get_logtext2($uowner, $gt_opts, @itemids);
    } else {
        $text = LJ::get_logtext($dbs, $gt_opts, @itemids);
    }
    foreach my $i (@itemids)
    {
        my $t = $text->{$i};
        my $evt = $evt_from_itemid{$i};

        # now that we have the subject, the event and the props, 
        # auto-translate them to UTF-8 if they're not in UTF-8.
        if ($LJ::UNICODE && $req->{'ver'} >= 1 && 
                $evt->{'props'}->{'unknown8bit'}) {
            my $error = 0;
            $t->[0] = LJ::text_convert($dbs, $t->[0], $uowner, \$error);
            $t->[1] = LJ::text_convert($dbs, $t->[1], $uowner, \$error);
            foreach (keys %{$evt->{'props'}}) {
                $evt->{'props'}->{$_} = LJ::text_convert($dbs, 
                    $evt->{'props'}->{$_}, $uowner, \$error);
            }
            return fail($err,208,"Cannot display this post. Please see $LJ::SITEROOT/support/encodings.bml for more information.")
                if $error;
        }

        if ($LJ::UNICODE && $req->{'ver'} < 1 && !$evt->{'props'}->{'unknown8bit'}) {
            unless ( LJ::is_ascii($t->[0]) && 
                     LJ::is_ascii($t->[1]) &&
                     LJ::is_ascii(join(' ', values %{$evt->{'props'}}) )) {
                # we want to fail the client that wants to get this entry
                # but we make an exception for selecttype=day, in order to allow at least
                # viewing the daily summary

                if ($req->{'selecttype'} eq 'day') {
                    $t->[0] = $t->[1] = '(cannot be shown)';
                } else {
                    return fail($err,207,"Cannot display/edit a Unicode post with a non-Unicode client. Please see $LJ::SITEROOT/support/encodings.bml for more information.");
                }
            }
        }

        if ($t->[0]) {
            $t->[0] =~ s/[\r\n]/ /g;
            $evt->{'subject'} = $t->[0];
        }

        # truncate
        if ($req->{'truncate'} >= 4) {
            my $original = $t->[1];
            if ($req->{'ver'} > 1) {
                $t->[1] = LJ::text_trim($t->[1], $req->{'truncate'} - 3, 0);
            } else {
                $t->[1] = LJ::text_trim($t->[1], 0, $req->{'truncate'} - 3);
            }
            # only append the elipsis if the text was actually truncated
            $t->[1] .= "..." if $t->[1] ne $original;
        }
        
        # line endings
        $t->[1] =~ s/\r//g;
        if ($req->{'lineendings'} eq "unix") {
            # do nothing.  native format.
        } elsif ($req->{'lineendings'} eq "mac") {
            $t->[1] =~ s/\n/\r/g;
        } elsif ($req->{'lineendings'} eq "space") {
            $t->[1] =~ s/\n/ /g;
        } elsif ($req->{'lineendings'} eq "dots") {
            $t->[1] =~ s/\n/ ... /g;
        } else { # "pc" -- default
            $t->[1] =~ s/\n/\r\n/g;
        }
        $evt->{'event'} = $t->[1];
    }

    # maybe we don't need the props after all
    if ($req->{'noprops'}) {
        foreach(@$events) { delete $_->{'props'}; }
    }

    return $res;
}

sub editfriends
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $userid = $u->{'userid'};
    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};
    my $sth;

    return fail($err,306) unless $dbh;

    my $res = {};

    ## first, figure out who the current friends are to save us work later
    my %curfriend;
    my $friend_count = 0;
    $sth = $dbh->prepare("SELECT u.user FROM user u, friends f ".
                         "WHERE u.userid=f.friendid AND f.userid=$userid");
    $sth->execute;
    while (my ($friend) = $sth->fetchrow_array) {
        $curfriend{$friend} = 1;
        $friend_count++;
    }
    $sth->finish;

    # perform the deletions
    my $did_deletes = 0;
  DELETEFRIEND:
    foreach (@{$req->{'delete'}})
    {
        my $deluser = LJ::canonical_username($_);
        next DELETEFRIEND unless ($curfriend{$deluser});

        my $friendid = LJ::get_userid($dbh, $deluser);
        $dbh->do("DELETE FROM friends WHERE userid=? AND friendid=?", undef,
                 $userid, $friendid);
        $did_deletes = 1;
        $friend_count--;
    }

    my $error_flag = 0;
    my $friends_added = 0;

    # perform the adds
  ADDFRIEND:
    foreach my $fa (@{$req->{'add'}})
    {
        unless (ref $fa eq "HASH") {
            $fa = { 'username' => $fa };
        }

        my $aname = LJ::canonical_username($fa->{'username'});
        unless ($aname) {
            $error_flag = 1;
            next ADDFRIEND;
        }

        $friend_count++ unless $curfriend{$aname};

        my $maxfriends = LJ::get_cap($u, "maxfriends");
        return fail($err,104,"Exceeded $maxfriends friends limit (now: $friend_count)")
            if ($friend_count > $maxfriends);

        my $fg = $fa->{'fgcolor'} || "#000000";
        my $bg = $fa->{'bgcolor'} || "#FFFFFF";
        if ($fg !~ /^\#[0-9A-F]{6,6}$/i || $bg !~ /^\#[0-9A-F]{6,6}$/i) {
            return fail($err,203,"Invalid color values");
        }

        my $row = LJ::load_user($dbs, $aname);

        # XXX - on some errors we fail out, on others we continue and try adding
        # any other users in the request. also, error message for redirect should
        # point the user to the redirected username.
        if (! $row) {
            $error_flag = 1;
        } elsif ($row->{'journaltype'} eq "Y" && 
                 ! LJ::get_cap($u, "synd_befriend")) {
            return fail($err,401);
        } elsif ($row->{'journaltype'} eq "Y" && 
                 ! LJ::can_add_syndicated($u, $row)) {
            return fail($err,403);
        } elsif ($row->{'journaltype'} eq "R") {
            return fail($err,154);
        } elsif ($row->{'statusvis'} ne "V") {
            $error_flag = 1;
        } else {
            $friends_added++;
            my $added = { 'username' => $aname,
                          'fullname' => $row->{'name'},
                      };
            if ($req->{'ver'} >= 1) {
                LJ::text_out(\$added->{'fullname'});
            }
            push @{$res->{'added'}}, $added;

            my $qfg = LJ::color_todb($fg);
            my $qbg = LJ::color_todb($bg);

            my $friendid = $row->{'userid'};

            my $gmask = $fa->{'groupmask'};
            if (! $gmask && $curfriend{$aname}) {
                # if no group mask sent, use the existing one if this is an existing friend
                my $sth = $dbh->prepare("SELECT groupmask FROM friends ".
                                        "WHERE userid=$userid AND friendid=$friendid");
                $sth->execute;
                $gmask = $sth->fetchrow_array;
            }
            # force bit 0 on.
            $gmask |= 1;

            $sth = $dbh->prepare("REPLACE INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) ".
                                 "VALUES ($userid, $friendid, $qfg, $qbg, $gmask)");
            $sth->execute;
            return fail($err,501,$dbh->errstr) if $dbh->err;

        }
    }

    # invalidate friends view cache (kinda lazy.... a better solution later
    # would be to only delete the matching packed items)
    LJ::invalidate_friends_view_cache($u) if $did_deletes || $friends_added;

    return fail($err,104) if $error_flag;
    return $res;
}

sub editfriendgroups
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);

    my $u = $flags->{'u'};
    my $userid = $u->{'userid'};
    my $dbr = $dbs->{'reader'};
    my $dbh = $dbs->{'dbh'};
    my $sth;

    return fail($err,306) unless $dbh;
    return fail($err,502) unless $dbr;

    my $res = {};

    ## make sure tree is how we want it
    $req->{'groupmasks'} = {} unless
        (ref $req->{'groupmasks'} eq "HASH");
    $req->{'set'} = {} unless
        (ref $req->{'set'} eq "HASH");
    $req->{'delete'} = [] unless
        (ref $req->{'delete'} eq "ARRAY");

    # Keep track of what bits are already set, so we can know later
    # whether to INSERT or UPDATE.
    my %bitset;
    $sth = $dbr->prepare("SELECT groupnum FROM friendgroup WHERE userid=$userid");
    $sth->execute;
    while (my ($bit) = $sth->fetchrow_array) {
        $bitset{$bit} = 1;
    }

    ## before we perform any DB operations, validate input text 
    # (groups' names) for correctness so we can fail gracefully
    if ($LJ::UNICODE) {
        foreach my $bit (keys %{$req->{'set'}})
        {
            my $name = $req->{'set'}->{$bit}->{'name'};
            return fail($err,207,"non-ASCII names require a Unicode-capable client")
                if $req->{'ver'} < 1 and not LJ::is_ascii($name);
            return fail($err,208,"Invalid group names. Please see $LJ::SITEROOT/support/encodings.bml for more information.")
                unless LJ::text_in($name);
        }
    }
    
    ## figure out deletions we'll do later
    foreach my $bit (@{$req->{'delete'}})
    {
        $bit += 0;
        next unless ($bit >= 1 && $bit <= 30);
        $bitset{$bit} = 0;  # so later we replace into, not update.
    }

    ## do additions/modifications ('set' hash)
    my %added;
    foreach my $bit (keys %{$req->{'set'}})
    {
        $bit += 0;
        next unless ($bit >= 1 && $bit <= 30);
        my $sa = $req->{'set'}->{$bit};
        my $name = LJ::text_trim($sa->{'name'}, LJ::BMAX_GRPNAME, LJ::CMAX_GRPNAME);

        # can't end with a slash
        $name =~ s!/$!!;        

        # setting it to name is like deleting it.
        unless ($name =~ /\S/) {
            push @{$req->{'delete'}}, $bit;
            next;
        }

        my $qname = $dbh->quote($name);
        my $qsort = defined $sa->{'sort'} ? ($sa->{'sort'}+0) : 50;
        my $qpublic = $dbh->quote(defined $sa->{'public'} ? ($sa->{'public'}+0) : 0);

        if ($bitset{$bit}) {
            # so update it
            my $sets;
            if (defined $sa->{'public'}) {
                $sets .= ", is_public=$qpublic";
            }
            $dbh->do("UPDATE friendgroup SET groupname=$qname, sortorder=$qsort ".
                     "$sets WHERE userid=$userid AND groupnum=$bit");
        } else {
            $dbh->do("REPLACE INTO friendgroup (userid, groupnum, ".
                     "groupname, sortorder, is_public) VALUES ".
                     "($userid, $bit, $qname, $qsort, $qpublic)");
        }
        $added{$bit} = 1;
    }


    ## do deletions ('delete' array)

    my ($dbcm, $dbcr, $clustered);
    if ($u->{'clusterid'}) {
        $dbcm = LJ::get_cluster_master($u);
        $dbcr = LJ::get_cluster_reader($u);
        $clustered = 1;
    }

    # ignore bits that aren't integers or that are outside 1-30 range
    my @delete_bits = grep {$_ >= 1 and $_ <= 30} map {$_+0} @{$req->{'delete'}};
    my $delete_mask = 0;
    foreach my $bit (@delete_bits) {
        $delete_mask |= (1 << $bit)
    }

    # remove the bits for deleted groups from all friends groupmasks
    if ($delete_mask) {
        $dbh->do("UPDATE friends".
                 "   SET groupmask = groupmask & ~$delete_mask".
                 " WHERE userid = $userid");
    }

    foreach my $bit (@delete_bits)
    {
        # remove all posts from allowing that group:
        my @posts_to_clean = ();
        if ($clustered) {
            $sth = $dbcr->prepare("SELECT jitemid FROM logsec2 WHERE journalid=$userid AND allowmask & (1 << $bit)");
        } else {
            $sth = $dbr->prepare("SELECT itemid FROM logsec WHERE ownerid=$userid AND allowmask & (1 << $bit)");
        }
        $sth->execute;
        while (my ($id) = $sth->fetchrow_array) { push @posts_to_clean, $id; }
        while (@posts_to_clean) {
            my @batch;
            if (scalar(@posts_to_clean) < 20) {
                @batch = @posts_to_clean;
                @posts_to_clean = ();
            } else {
                @batch = splice(@posts_to_clean, 0, 20);
            }
            my $in = join(",", @batch);
            if ($clustered) {
                $dbcm->do("UPDATE log2 SET allowmask=allowmask & ~(1 << $bit) ".
                         "WHERE journalid=$userid AND jitemid IN ($in) AND security='usemask'");
                $dbcm->do("UPDATE logsec2 SET allowmask=allowmask & ~(1 << $bit) ".
                         "WHERE journalid=$userid AND jitemid IN ($in)");
            } else {
                $dbh->do("UPDATE log SET allowmask=allowmask & ~(1 << $bit) ".
                         "WHERE itemid IN ($in) AND security='usemask'");
                $dbh->do("UPDATE logsec SET allowmask=allowmask & ~(1 << $bit) ".
                         "WHERE ownerid=$userid AND itemid IN ($in)");
            }

        }

        # remove the friend group, unless we just added it this transaction
        unless ($added{$bit}) {
            $sth = $dbh->prepare("DELETE FROM friendgroup WHERE ".
                                 "userid=$userid AND groupnum=$bit");
            $sth->execute;
        }
    }

    ## change friends' masks
    foreach my $friend (keys %{$req->{'groupmasks'}})
    {
        my $mask = int($req->{'groupmasks'}->{$friend}) | 1;
        $dbh->do("UPDATE friends SET groupmask=$mask ".
                 "WHERE userid=$userid AND friendid=?",
                 undef, LJ::get_userid($dbs, $friend));
    }

    # return value for this is nothing.
    return {};
}

sub list_friends
{
    my ($dbs, $u, $opts) = @_;
    my $dbr = $dbs->{'reader'};

    my $limitnum = $opts->{'limit'}+0;
    my $where = "u.userid=f.friendid AND f.userid=$u->{'userid'}";
    if ($opts->{'friendof'}) {
        $where = "u.userid=f.userid AND f.friendid=$u->{'userid'} AND u.statusvis='V'";
    }

    my $bday = $opts->{'includebdays'} ? "u.bdate, u.allow_infoshow," : ""; 
    my $limit = $limitnum ? "LIMIT $limitnum" : "";
    my $sth = $dbr->prepare("SELECT u.user AS 'friend', $bday u.name,".
                            "u.journaltype, u.statusvis, f.fgcolor, f.bgcolor, f.groupmask ".
                            "FROM user u, friends f WHERE $where ORDER BY u.user $limit");
    $sth->execute;
    my @friends;
    push @friends, $_ while $_ = $sth->fetchrow_hashref;
    $sth->finish;

    my $res = [];
    foreach my $f (@friends)
    {
        my $r =  { 'username' => $f->{'friend'},
                   'fullname' => $f->{'name'},
               };
        $r->{'birthday'} = $f->{'bdate'} 
            unless $f->{'allow_infoshow'} ne 'Y' || !$f->{'bdate'} 
                || $f->{'bdate'} eq '0000-00-00';

        $r->{'fgcolor'} = LJ::color_fromdb($f->{'fgcolor'});
        $r->{'bgcolor'} = LJ::color_fromdb($f->{'bgcolor'});
        if (! $opts->{'friendof'} && $f->{'groupmask'} != 1) {
            $r->{"groupmask"} = $f->{'groupmask'};
        }
        if ($f->{'journaltype'} eq "C") {
            $r->{"type"} = "community";
        }
        $r->{"status"} = {
            'D' => "deleted",
            'S' => "suspended",
            'X' => "purged",
        }->{$f->{'statusvis'}} if $f->{'statusvis'} ne 'V';

        push @$res, $r;
    }
    return $res;
}

sub syncitems
{
    my ($dbs, $req, $err, $flags) = @_;
    return undef unless authenticate($dbs, $req, $err, $flags);
    return undef unless check_altusage($dbs, $req, $err, $flags);

    my $ownerid = $flags->{'ownerid'};
    my $uowner = $flags->{'u_owner'} || $flags->{'u'};
    my $dbr = $dbs->{'reader'};
    my ($date, $sth);

    # cluster differences
    my ($db, $table) = ($dbs->{'dbh'}, "syncupdates");
    ($db, $table) = (LJ::get_cluster_reader($uowner), "syncupdates2")
        if $uowner->{'clusterid'};

    return fail($err,502) unless $db;

    ## have a valid date?
    $date = $req->{'lastsync'};
    if ($date) {
        return fail($err,203,"Invalid date format")
            unless ($date =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/);
    } else {
        $date = "0000-00-00 00:00:00";
    }

    my $LIMIT = 500;

    my $total = $db->selectrow_array("SELECT COUNT(*) FROM $table WHERE ".
                                     "userid=$ownerid AND atime >= '$date'");

    $sth = $db->prepare("SELECT atime, nodetype, nodeid, atype FROM ".
                        "$table WHERE userid=$ownerid AND ".
                        "atime >= '$date' ORDER BY atime LIMIT $LIMIT");
    $sth->execute;
    return fail($err,501,$db->errstr) if $db->err;

    my $res = {};
    my $list = $res->{'syncitems'} = [];
    my $ct = 0;
    while (my ($atime, $nodetype, $nodeid, $atype) = $sth->fetchrow_array) {
        $ct++;
        push @$list, { 'item' => "$nodetype-$nodeid",
                       'action' => $atype,
                       'time' => $atime,
                   };
    }
    $res->{'count'} = $ct;
    $res->{'total'} = $total;
    return $res;
}

sub consolecommand
{
    my ($dbs, $req, $err, $flags) = @_;

    # TODO: LJ::Con doesn't yet support $dbs/$dbarg
    my $dbh = $dbs->{'dbh'};
    return fail($err,502) unless $dbh;

    # logging in isn't necessary, but most console commands do require it
    my $remote = undef;
    $remote = $flags->{'u'} if authenticate($dbs, $req, $err, $flags);

    my $res = {};
    my $cmdout = $res->{'results'} = [];

    foreach my $cmd (@{$req->{'commands'}})
    {
        # callee can pre-parse the args, or we can do it bash-style
        $cmd = [ LJ::Con::parse_line($cmd) ] unless (ref $cmd eq "ARRAY");

        my @output;
        my $rv = LJ::Con::execute($dbh, $remote, $cmd, \@output);
        push @{$cmdout}, {
            'success' => $rv,
            'output' => \@output,
        };
    }

    return $res;
}

sub login_message
{
    my ($dbs, $req, $res, $flags) = @_;
    my $u = $flags->{'u'};

    my $msg = sub {
        my $code = shift;
        my $args = shift || {};
        $args->{'sitename'} = $LJ::SITENAME;
        $args->{'siteroot'} = $LJ::SITEROOT;
        $res->{'message'} = translate($u, $code, $args);
    };

    return $msg->("readonly")          if LJ::get_cap($u, "readonly");
    return $msg->("not_validated")     if ($u->{'status'} eq "N" and not $LJ::EVERYONE_VALID);
    return $msg->("must_revalidate")   if ($u->{'status'} eq "T" and not $LJ::EVERYONE_VALID);
    return $msg->("mail_bouncing")     if $u->{'status'} eq "B";

    my @checkpass = LJ::run_hooks("bad_password", $u->{'password'});
    return $msg->("bad_password")      if (@checkpass and $checkpass[0]->[0]);
    
    return $msg->("old_win32_client")  if $req->{'clientversion'} =~ /^Win32-MFC\/(1.2.[0123456])$/;
    return $msg->("old_win32_client")  if $req->{'clientversion'} =~ /^Win32-MFC\/(1.3.[01234])\b/;
    return $msg->("hello_test")        if $u->{'user'} eq "test";
}

sub list_friendgroups
{
    my $dbs = shift;
    my $u = shift;

    my $res = [];
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT groupnum, groupname, sortorder, is_public ".
                            "FROM friendgroup WHERE userid=$u->{'userid'} ".
                            "ORDER BY sortorder");
    $sth->execute;
    while (my ($gid, $name, $sort, $public) = $sth->fetchrow_array) {
        push @$res, { 'id' => $gid,
                      'name' => $name,
                      'sortorder' => $sort,
                      'public' => $public };
    }
    $sth->finish;
    return $res;
}

sub list_usejournals
{
    my $dbs = shift;
    my $u = shift;

    my $res = [];

    my $dbr = $dbs->{'reader'};
    my $sth = $dbr->prepare("SELECT u.user FROM user u, logaccess la ".
                            "WHERE la.ownerid=u.userid AND ".
                            "u.statusvis='V' AND ".
                            "la.posterid=$u->{'userid'} ORDER BY u.user");
    $sth->execute;
    while (my $u = $sth->fetchrow_array) {
        push @$res, $u;
    }
    $sth->finish;
    return $res;
}

sub hash_menus
{
    my $dbs = shift;
    my $u = shift;
    my $user = $u->{'user'};

    my $menu = [
                { 'text' => "Recent Entries",
                  'url' => "$LJ::SITEROOT/users/$user/", },
                { 'text' => "Calendar View",
                  'url' => "$LJ::SITEROOT/users/$user/calendar", },
                { 'text' => "Friends View",
                  'url' => "$LJ::SITEROOT/users/$user/friends", },
                { 'text' => "-", },
                { 'text' => "Your Profile",
                  'url' => "$LJ::SITEROOT/userinfo.bml?user=$user", },
                { 'text' => "Your To-Do List",
                  'url' => "$LJ::SITEROOT/todo/?user=$user", },
                { 'text' => "-", },
                { 'text' => "Change Settings",
                  'sub' => [ { 'text' => "Personal Info",
                               'url' => "$LJ::SITEROOT/editinfo.bml", },
                             { 'text' => "Journal Settings",
                               'url' =>"$LJ::SITEROOT/modify.bml", }, ] },
                { 'text' => "-", },
                { 'text' => "Support",
                  'url' => "$LJ::SITEROOT/support/", }
                ];

    LJ::run_hooks("modify_login_menu", {
        'dbs' => $dbs,
        'menu' => $menu,
        'u' => $u,
        'user' => $user,
    });

    return $menu;
}

sub list_pickws
{
    my $dbs = shift;
    my $u = shift;

    my $dbr = $dbs->{'reader'};
    my $res = [];

    my $sth = $dbr->prepare("SELECT k.keyword, m.picid FROM userpicmap m, keywords k ".
                            "WHERE m.userid=$u->{'userid'} AND m.kwid=k.kwid ".
                            "ORDER BY k.keyword");
    $sth->execute;
    while (my ($kw, $id) = $sth->fetchrow_array) {
        $kw =~ s/[\n\r\0]//g;  # used to be a bug that allowed these characters to get in.
        push @$res, [ $kw, $id ];
    }
    return $res;
}

sub list_moods
{
    my $dbs = shift;
    my $mood_max = int(shift);

    LJ::load_moods($dbs);

    my $res = [];
    return $res unless ($mood_max < $LJ::CACHED_MOOD_MAX);

    for (my $id = $mood_max+1; $id <= $LJ::CACHED_MOOD_MAX; $id++) {
        next unless defined $LJ::CACHE_MOODS{$id};
        my $mood = $LJ::CACHE_MOODS{$id};
        push @$res, { 'id' => $id,
                      'name' => $mood->{'name'},
                      'parent' => $mood->{'parent'} };
    }

    return $res;
}

sub check_altusage
{
    my ($dbs, $req, $err, $flags) = @_;

    # see note in ljlib.pl::can_use_journal about why we return
    # both 'ownerid' and 'u_owner' in $flags

    my $alt = $req->{'usejournal'};
    my $u = $flags->{'u'};
    $flags->{'ownerid'} = $u->{'userid'};

    # all good if not using an alt journal
    return 1 unless $alt;

    # complain if the username is invalid
    return fail($err,206) unless LJ::canonical_username($alt);

    # allow usage if we're told explicitly that it's okay
    if ($flags->{'usejournal_okay'}) {
        $flags->{'u_owner'} = LJ::load_user($dbs, $alt);
        $flags->{'ownerid'} = $flags->{'u_owner'}->{'userid'};
        return 1 if $flags->{'ownerid'};
        return fail($err,206);
    }

    # otherwise, check logaccess table:
    my $info = {};
    my $canuse = LJ::can_use_journal($dbs, $u->{'userid'}, $req->{'usejournal'}, $info);
    $flags->{'ownerid'} = $info->{'ownerid'};
    $flags->{'u_owner'} = $info->{'u_owner'};

    return 1 if $canuse || $flags->{'ignorecanuse'};

    # not allowed to access it
    return fail($err,300);
}

sub authenticate
{
    my ($dbs, $req, $err, $flags) = @_;

    my $username = $req->{'username'};
    return fail($err,200) unless $username;
    return fail($err,100) unless LJ::canonical_username($username);

    my $u = $flags->{'u'};
    unless ($u) {
        my $dbr = $dbs->{'reader'};
        return fail($err,502) unless $dbr;
        my $quser = $dbr->quote($username);
        my $other = $LJ::UNICODE ? ", oldenc" : "";
        my $sth = $dbr->prepare("SELECT user, userid, journaltype, name, ".
                                "password, status, statusvis, caps, ".
                                "clusterid, dversion, defaultpicid ".
                                "$other FROM user WHERE user=$quser");
        $sth->execute;
        return fail($err,501,$dbr->errstr) if $dbr->err;
        $u = $sth->fetchrow_hashref;
    }

    return fail($err,100) unless $u;
    return fail($err,100) if ($u->{'statusvis'} eq "X");

    my $ip_banned = 0;
    unless ($flags->{'nopassword'} ||
            $flags->{'noauth'} ||
            LJ::auth_okay($username,
                          $req->{'password'},
                          $req->{'hpassword'},
                          $u->{'password'},
                          \$ip_banned))
    {
        return fail($err,402) if $ip_banned;
        return fail($err,101);
    }
    # remember the user record for later.
    $flags->{'u'} = $u;
    return 1;
}

sub fail
{
    my $err = shift;
    my $code = shift;
    my $des = shift;
    $code .= ":$des" if $des;
    $$err = $code if (ref $err eq "SCALAR");
    return undef;
}

#### Old interface (flat key/values) -- wrapper aruond LJ::Protocol
package LJ;

sub do_request
{
    # get the request and response hash refs
    my ($db_arg, $req, $res, $flags) = @_;

    # initialize some stuff
    my $dbs = LJ::make_dbs_from_arg($db_arg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    %{$res} = ();                      # clear the given response hash
    $flags = {} unless (ref $flags eq "HASH");

    my $user = LJ::canonical_username($req->{'user'});
    my $quser = $dbh->quote($user);

    # check for an alive database connection
    unless ($dbh) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Server error: cannot connect to database.";
        return;
    }

    # did they send a mode?
    unless ($req->{'mode'}) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No mode specified.";
        return;
    }

    unless ($user) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = "Client error: No username sent.";
        return;
    }

    ### see if the server's under maintenance now
    if ($LJ::SERVER_DOWN) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = $LJ::SERVER_DOWN_MESSAGE;
        return;
    }

    ## dispatch wrappers
    if ($req->{'mode'} eq "login") {
        return login($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriendgroups") {
        return getfriendgroups($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getfriends") {
        return getfriends($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "friendof") {
        return friendof($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "checkfriends") {
        return checkfriends($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getdaycounts") {
        return getdaycounts($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "postevent") {
        return postevent($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "editevent") {
        return editevent($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "syncitems") {
        return syncitems($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "getevents") {
        return getevents($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "editfriends") {
        return editfriends($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "editfriendgroups") {
        return editfriendgroups($dbs, $req, $res, $flags);
    }
    if ($req->{'mode'} eq "consolecommand") {
        return consolecommand($dbs, $req, $res, $flags);
    }

    ### unknown mode!
    $res->{'success'} = "FAIL";
    $res->{'errmsg'} = "Client error: Unknown mode ($req->{'mode'})";
    return;
}

## flat wrapper
sub login
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "login", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'name'} = $rs->{'fullname'};
    $res->{'message'} = $rs->{'message'} if $rs->{'message'};
    $res->{'fastserver'} = 1 if $rs->{'fastserver'};

    # shared journals
    my $access_count = 0;
    foreach my $user (@{$rs->{'usejournals'}}) {
        $access_count++;
        $res->{"access_${access_count}"} = $user;
    }
    if ($access_count) {
        $res->{"access_count"} = $access_count;
    }

    # friend groups
    populate_friend_groups($res, $rs->{'friendgroups'});

    my $flatten = sub {
        my ($prefix, $listref) = @_;
        my $ct = 0;
        foreach (@$listref) {
            $ct++;
            $res->{"${prefix}_$ct"} = $_;
        }
        $res->{"${prefix}_count"} = $ct;
    };

    ### picture keywords
    $flatten->("pickw", $rs->{'pickws'})
        if defined $req->{"getpickws"};
    $flatten->("pickwurl", $rs->{'pickwurls'})
        if defined $req->{"getpickwurls"};
    $res->{'defaultpicurl'} = $rs->{'defaultpicurl'} if $rs->{'defaultpicurl'};

    ### report new moods that this client hasn't heard of, if they care
    if (defined $req->{"getmoods"}) {
        my $mood_count = 0;
        foreach my $m (@{$rs->{'moods'}}) {
            $mood_count++;
            $res->{"mood_${mood_count}_id"} = $m->{'id'};
            $res->{"mood_${mood_count}_name"} = $m->{'name'};
        }
        if ($mood_count) {
            $res->{"mood_count"} = $mood_count;
        }
    }

    #### send web menus
    if ($req->{"getmenus"} == 1) {
        my $menu = $rs->{'menus'};
        my $menu_num = 0;
        populate_web_menu($res, $menu, \$menu_num);
    }

    return 1;
}

## flat wrapper
sub getfriendgroups
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "getfriendgroups", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }
    $res->{'success'} = "OK";
    populate_friend_groups($res, $rs->{'friendgroups'});

    return 1;
}

## flat wrapper
sub getfriends
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "getfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    if ($req->{'includegroups'}) {
        populate_friend_groups($res, $rs->{'friendgroups'});
    }
    if ($req->{'includefriendof'}) {
        populate_friends($res, "friendof", $rs->{'friendofs'});
    }
    populate_friends($res, "friend", $rs->{'friends'});

    return 1;
}

## flat wrapper
sub friendof
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "friendof", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    populate_friends($res, "friendof", $rs->{'friendofs'});
    return 1;
}

## flat wrapper
sub checkfriends
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "checkfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'new'} = $rs->{'new'};
    $res->{'lastupdate'} = $rs->{'lastupdate'};
    $res->{'interval'} = $rs->{'interval'};
    return 1;
}

## flat wrapper
sub getdaycounts
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "getdaycounts", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    foreach my $d (@{ $rs->{'daycounts'} }) {
        $res->{$d->{'date'}} = $d->{'count'};
    }
    return 1;
}

## flat wrapper
sub syncitems
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "syncitems", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'sync_total'} = $rs->{'total'};
    $res->{'sync_count'} = $rs->{'count'};

    my $ct = 0;
    foreach my $s (@{ $rs->{'syncitems'} }) {
        $ct++;
        foreach my $a (qw(item action time)) {
            $res->{"sync_${ct}_$a"} = $s->{$a};
        }
    }
    return 1;
}

## flat wrapper: limited functionality.  (1 command only, server-parsed only)
sub consolecommand
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    delete $rq->{'command'};

    $rq->{'commands'} = [ $req->{'command'} ];

    my $rs = LJ::Protocol::do_request($dbs, "consolecommand", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'cmd_success'} = $rs->{'results'}->[0]->{'success'};
    $res->{'cmd_line_count'} = 0;
    foreach my $l (@{$rs->{'results'}->[0]->{'output'}}) {
        $res->{'cmd_line_count'}++;
        my $line = $res->{'cmd_line_count'};
        $res->{"cmd_line_${line}_type"} = $l->[0]
            if $l->[0];
        $res->{"cmd_line_${line}"} = $l->[1];
    }

    $res->{'success'} = "OK";

}

## flat wrapper
sub editfriends
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    $rq->{'add'} = [];
    $rq->{'delete'} = [];

    foreach (keys %$req) {
        if (/^editfriend_add_(\d+)_user$/) {
            my $n = $1;
            next unless ($req->{"editfriend_add_${n}_user"} =~ /\S/);
            my $fa = { 'username' => $req->{"editfriend_add_${n}_user"},
                       'fgcolor' => $req->{"editfriend_add_${n}_fg"},
                       'bgcolor' => $req->{"editfriend_add_${n}_bg"},
                       'groupmask' => $req->{"editfriend_add_${n}_groupmask"},
                   };
            push @{$rq->{'add'}}, $fa;
        } elsif (/^editfriend_delete_(\w+)$/) {
            push @{$rq->{'delete'}}, $1;
        }
    }

    my $rs = LJ::Protocol::do_request($dbs, "editfriends", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";

    my $ct = 0;
    foreach my $fa (@{ $rs->{'added'} }) {
        $ct++;
        $res->{"friend_${ct}_user"} = $fa->{'username'};
        $res->{"friend_${ct}_name"} = $fa->{'fullname'};
    }

    $res->{'friends_added'} = $ct;

    return 1;
}

## flat wrapper
sub editfriendgroups
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    $rq->{'groupmasks'} = {};
    $rq->{'set'} = {};
    $rq->{'delete'} = [];

    foreach (keys %$req) {
        if (/^efg_set_(\d+)_name$/) {
            next unless ($req->{$_} ne "");
            my $n = $1;
            my $fs = {
                'name' => $req->{"efg_set_${n}_name"},
                'sort' => $req->{"efg_set_${n}_sort"},
            };
            if (defined $req->{"efg_set_${n}_public"}) {
                $fs->{'public'} = $req->{"efg_set_${n}_public"};
            }
            $rq->{'set'}->{$n} = $fs;
        }
        elsif (/^efg_delete_(\d+)$/) {
            if ($req->{$_}) {
                # delete group if value is true
                push @{$rq->{'delete'}}, $1;
            }
        }
        elsif (/^editfriend_groupmask_(\w+)$/) {
            $rq->{'groupmasks'}->{$1} = $req->{$_};
        }
    }

    my $rs = LJ::Protocol::do_request($dbs, "editfriendgroups", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    return 1;
}

sub flatten_props
{
    my ($req, $rq) = @_;

    ## changes prop_* to props hashref
    foreach my $k (keys %$req) {
        next unless ($k =~ /^prop_(.+)/);
        $rq->{'props'}->{$1} = $req->{$k};
    }
}

## flat wrapper
sub postevent
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    flatten_props($req, $rq);

    my $rs = LJ::Protocol::do_request($dbs, "postevent", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'itemid'} = $rs->{'itemid'};
    $res->{'anum'} = $rs->{'anum'} if defined $rs->{'anum'};
    return 1;
}

## flat wrapper
sub editevent
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);
    flatten_props($req, $rq);

    my $rs = LJ::Protocol::do_request($dbs, "editevent", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    $res->{'success'} = "OK";
    $res->{'itemid'} = $rs->{'itemid'};
    $res->{'anum'} = $rs->{'anum'} if defined $rs->{'anum'};
    return 1;
}

## flat wrapper
sub getevents
{
    my ($dbs, $req, $res, $flags) = @_;

    my $err = 0;
    my $rq = upgrade_request($req);

    my $rs = LJ::Protocol::do_request($dbs, "getevents", $rq, \$err, $flags);
    unless ($rs) {
        $res->{'success'} = "FAIL";
        $res->{'errmsg'} = LJ::Protocol::error_message($err);
        return 0;
    }

    my $ect = 0;
    my $pct = 0;
    foreach my $evt (@{$rs->{'events'}}) {
        $ect++;
        foreach my $f (qw(itemid eventtime security allowmask subject anum poster)) {
            if (defined $evt->{$f}) {
                $res->{"events_${ect}_$f"} = $evt->{$f};
            }
        }
        $res->{"events_${ect}_event"} = LJ::eurl($evt->{'event'});

        if ($evt->{'props'}) {
            foreach my $k (sort keys %{$evt->{'props'}}) {
                $pct++;
                $res->{"prop_${pct}_itemid"} = $evt->{'itemid'};
                $res->{"prop_${pct}_name"} = $k;
                $res->{"prop_${pct}_value"} = $evt->{'props'}->{$k};
            }
        }
    }

    unless ($req->{'noprops'}) {
        $res->{'prop_count'} = $pct;
    }
    $res->{'events_count'} = $ect;
    $res->{'success'} = "OK";

    return 1;
}


sub populate_friends
{
    my ($res, $pfx, $list) = @_;
    my $count = 0;
    foreach my $f (@$list)
    {
        $count++;
        $res->{"${pfx}_${count}_name"} = $f->{'fullname'};
        $res->{"${pfx}_${count}_user"} = $f->{'username'};
        $res->{"${pfx}_${count}_birthday"} = $f->{'birthday'} if $f->{'birthday'}; 
        $res->{"${pfx}_${count}_bg"} = $f->{'bgcolor'};
        $res->{"${pfx}_${count}_fg"} = $f->{'fgcolor'};
        if (defined $f->{'groupmask'}) {
            $res->{"${pfx}_${count}_groupmask"} = $f->{'groupmask'};
        }
        if (defined $f->{'type'}) {
            $res->{"${pfx}_${count}_type"} = $f->{'type'};
        }
        if (defined $f->{'status'}) {
            $res->{"${pfx}_${count}_status"} = $f->{'status'};
        }
    }
    $res->{"${pfx}_count"} = $count;
}


sub upgrade_request
{
    my $r = shift;
    my $new = { %{ $r } };
    $new->{'username'} = $r->{'user'};

    # but don't delete $r->{'user'}, as it might be, say, %FORM,
    # that'll get reused in a later request in, say, update.bml after
    # the login before postevent.  whoops.

    return $new;
}

## given a $res hashref and friend group subtree (arrayref), flattens it
sub populate_friend_groups
{
    my ($res, $fr) = @_;

    my $maxnum = 0;
    foreach my $fg (@$fr)
    {
        my $num = $fg->{'id'};
        $res->{"frgrp_${num}_name"} = $fg->{'name'};
        $res->{"frgrp_${num}_sortorder"} = $fg->{'sortorder'};
        if ($fg->{'public'}) {
            $res->{"frgrp_${num}_public"} = 1;
        }
        if ($num > $maxnum) { $maxnum = $num; }
    }
    $res->{'frgrp_maxnum'} = $maxnum;
}

## given a menu tree, flattens it into $res hashref
sub populate_web_menu
{
    my ($res, $menu, $numref) = @_;
    my $mn = $$numref;  # menu number
    my $mi = 0;         # menu item
    foreach my $it (@$menu) {
        $mi++;
        $res->{"menu_${mn}_${mi}_text"} = $it->{'text'};
        if ($it->{'text'} eq "-") { next; }
        if ($it->{'sub'}) {
            $$numref++;
            $res->{"menu_${mn}_${mi}_sub"} = $$numref;
            &populate_web_menu($res, $it->{'sub'}, $numref);
            next;

        }
        $res->{"menu_${mn}_${mi}_url"} = $it->{'url'};
    }
    $res->{"menu_${mn}_count"} = $mi;
}

1;
