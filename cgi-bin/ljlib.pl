#!/usr/bin/perl
#
# <LJDEP>
# lib: DBI::, Digest::MD5, URI::URL
# lib: cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/ljpoll.pl
# lib: cgi-bin/cleanhtml.pl
# link: htdocs/paidaccounts/index.bml, htdocs/users, htdocs/view/index.bml
# hook: canonicalize_url, name_caps, name_caps_short, post_create
# hook: validate_get_remote
# </LJDEP>

use strict;
use DBI;
use Digest::MD5 qw(md5_hex);
use Text::Wrap;
use MIME::Lite;
use HTTP::Date qw();
use IO::Socket;
use Unicode::MapUTF8;

require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";

# $LJ::PROTOCOL_VER is the version of the client-server protocol
# used uniformly by server code which uses the protocol.
$LJ::PROTOCOL_VER = ($LJ::UNICODE ? "1" : "0");

# constants
$LJ::EndOfTime = 2147483647;

# width constants. BMAX_ constants are restrictions on byte width,
# CMAX_ on character width (character means byte unless $LJ::UNICODE,
# in which case it means a UTF-8 character).

$LJ::BMAX_SUBJECT = 255;   # *_SUBJECT for journal events, not comments
$LJ::CMAX_SUBJECT = 100;
$LJ::BMAX_COMMENT = 9000;
$LJ::CMAX_COMMENT = 4300;
$LJ::BMAX_MEMORY  = 150;
$LJ::CMAX_MEMORY  = 80;
$LJ::BMAX_NAME    = 100;
$LJ::CMAX_NAME    = 50;
$LJ::BMAX_KEYWORD = 80;
$LJ::CMAX_KEYWORD = 40;
$LJ::BMAX_PROP    = 255;   # logprop[2]/talkprop[2]/userproplite (not userprop)
$LJ::CMAX_PROP    = 100;
$LJ::BMAX_GRPNAME = 60;
$LJ::CMAX_GRPNAME = 30;
$LJ::BMAX_EVENT   = 65535;
$LJ::CMAX_EVENT   = 65535;

# declare views (calls into ljviews.pl)
@LJ::views = qw(lastn friends calendar day);
%LJ::viewinfo = (
                 "lastn" => {
                     "creator" => \&create_view_lastn,
                     "des" => "Most Recent Events",
                 },
                 "calendar" => {
                     "creator" => \&create_view_calendar,
                     "des" => "Calendar",
                 },
                 "day" => {
                     "creator" => \&create_view_day,
                     "des" => "Day View",
                 },
                 "friends" => {
                     "creator" => \&create_view_friends,
                     "des" => "Friends View",
                 },
                 "rss" => {
                     "creator" => \&create_view_rss,
                     "des" => "RSS View (XML)",
                     "nostyle" => 1,
                 },
                 "info" => {
                     # just a redirect to userinfo.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 }
                 );

## we want to set this right away, so when we get a HUP signal later
## and our signal handler sets it to true, perl doesn't need to malloc,
## since malloc may not be thread-safe and we could core dump.
## see LJ::clear_caches and LJ::handle_caches
$LJ::CLEAR_CACHES = 0;

## if this library is used in a BML page, we don't want to destroy BML's
## HUP signal handler.
if ($SIG{'HUP'}) {
    my $oldsig = $SIG{'HUP'};
    $SIG{'HUP'} = sub {
        &{$oldsig};
        LJ::clear_caches();
    };
} else {
    $SIG{'HUP'} = \&LJ::clear_caches;
}


package LJ;

# <LJFUNC>
# name: LJ::get_newids
# des: Lookup an old global ID and see what journal it belongs to and its new ID.
# info: Interface to [dbtable[oldids]] table (URL compatability)
# returns: Undef if non-existent or unconverted, or arrayref of [$userid, $newid].
# args: area, oldid
# des-area: The "area" of the id.  Legal values are "L" (log), to lookup an old itemid,
#           or "T" (talk) to lookup an old talkid.
# des-oldid: The old globally-unique id of the item.
# </LJFUNC>
sub get_newids
{
    my $dbarg = shift;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;

    my $area = $dbh->quote(shift);
    my $oldid = $dbh->quote(shift);
    my $db = LJ::get_dbh("oldids") || $dbr;
    return $db->selectrow_arrayref("SELECT userid, newid FROM oldids ".
                                   "WHERE area=$area AND oldid=$oldid");
}

# <LJFUNC>
# class: db
# name: LJ::dbs_selectrow_array
# des: Like DBI's selectrow_array, but working on a $dbs preferring the slave.
# info: Given a dbset and a query, will try to query the slave first.
#       Falls back to master if not in slave yet.  See also
#       [func[LJ::dbs_selectrow_hashref]].
# returns: In scalar context, the first column selected.  In list context,
#          the entire row.
# args: dbs, query
# des-query: The select query to run.
# </LJFUNC>
sub dbs_selectrow_array
{
    my $dbs = shift;
    my $query = shift;

    my @dbl = ($dbs->{'dbh'});
    if ($dbs->{'has_slave'}) { unshift @dbl, $dbs->{'dbr'}; }
    foreach my $db (@dbl) {
        my $ans = $db->selectrow_arrayref($query);
        return wantarray() ? @$ans : $ans->[0] if defined $ans;
    }
    return undef;
}

# <LJFUNC>
# class: db
# name: LJ::dbs_selectrow_hashref
# des: Like DBI's selectrow_hashref, but working on a $dbs preferring the slave.
# info: Given a dbset and a query, will try to query the slave first.
#       Falls back to master if not in slave yet.  See also
#       [func[LJ::dbs_selectrow_array]].
# returns: Hashref, or undef if no row found in either slave or master.
# args: dbs, query
# des-query: The select query to run.
# </LJFUNC>
sub dbs_selectrow_hashref
{
    my $dbs = shift;
    my $query = shift;

    my @dbl = ($dbs->{'dbh'});
    if ($dbs->{'has_slave'}) { unshift @dbl, $dbs->{'dbr'}; }
    foreach my $db (@dbl) {
        my $ans = $db->selectrow_hashref($query);
        return $ans if defined $ans;
    }
    return undef;
}

# <LJFUNC>
# name: LJ::get_friend_items
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_friend_items
{
    my $dbarg = shift;
    my $opts = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;

    my $userid = $opts->{'userid'}+0;

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    LJ::load_remote($dbs, $remote);
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($dbs, $remoteid);
    }

    my @items = ();
    my $itemshow = $opts->{'itemshow'}+0;
    my $skip = $opts->{'skip'}+0;
    my $getitems = $itemshow + $skip;

    my $owners_ref = (ref $opts->{'owners'} eq "HASH") ? $opts->{'owners'} : {};
    my $filter = $opts->{'filter'}+0;

    # sanity check:
    $skip = 0 if ($skip < 0);

    # what do your friends think of remote viewer?  what security level?
    # but only if the remote viewer is a person, not a community/shared journal.
    my $gmask_from = {};
    if ($remote && $remote->{'journaltype'} eq "P") {
        $sth = $dbr->prepare("SELECT ff.userid, ff.groupmask FROM friends fu, friends ff WHERE fu.userid=$userid AND fu.friendid=ff.userid AND ff.friendid=$remoteid");
        $sth->execute;
        while (my ($friendid, $mask) = $sth->fetchrow_array) {
            $gmask_from->{$friendid} = $mask;
        }
        $sth->finish;
    }

    my $filtersql;
    if ($filter) {
        if ($remoteid == $userid) {
            $filtersql = "AND f.groupmask & $filter";
        }
    }

    my @friends_buffer = ();
    my $total_loaded = 0;
    my $buffer_unit = int($getitems * 1.5);  # load a bit more first to avoid 2nd load

    my $get_next_friend = sub
    {
        # return one if we already have some loaded.
        if (@friends_buffer) {
            return $friends_buffer[0];
        }

        # load another batch if we just started or
        # if we just finished a batch.
        if ($total_loaded % $buffer_unit == 0)
        {
            my $sth = $dbr->prepare("SELECT u.userid, $LJ::EndOfTime-UNIX_TIMESTAMP(uu.timeupdate), u.clusterid FROM friends f, userusage uu, user u WHERE f.userid=$userid AND f.friendid=uu.userid AND f.friendid=u.userid $filtersql AND u.statusvis='V' AND uu.timeupdate IS NOT NULL ORDER BY 2 LIMIT $total_loaded, $buffer_unit");
            $sth->execute;

            while (my ($userid, $update, $clusterid) = $sth->fetchrow_array) {
                push @friends_buffer, [ $userid, $update, $clusterid ];
                $total_loaded++;
            }

            # return one if we just found some fine, else we're all
            # out and there's nobody else to load.
            if (@friends_buffer) {
                return $friends_buffer[0];
            } else {
                return undef;
            }
        }

        # otherwise we must've run out.
        return undef;
    };

    my $loop = 1;
    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14;  # 2 week default.
    my $lastmax = $LJ::EndOfTime - time() + $max_age;
    my $itemsleft = $getitems;
    my $fr;

    while ($loop && ($fr = $get_next_friend->()))
    {
        shift @friends_buffer;

        # load the next recent updating friend's recent items
        my $friendid = $fr->[0];

        my @newitems = LJ::get_recent_items($dbs, {
            'clustersource' => 'slave',  # no effect for cluster 0
            'clusterid' => $fr->[2],
            'userid' => $friendid,
            'remote' => $remote,
            'itemshow' => $itemsleft,
            'skip' => 0,
            'gmask_from' => $gmask_from,
            'friendsview' => 1,
            'notafter' => $lastmax,
        });

        # stamp each with clusterid if from cluster, so ljviews and other
        # callers will know which items are old (no/0 clusterid) and which
        # are new
        if ($fr->[2]) {
            foreach (@newitems) { $_->{'clusterid'} = $fr->[2]; }
        }

        if (@newitems)
        {
            push @items, @newitems;

            $opts->{'owners'}->{$friendid} = 1;

            $itemsleft--; # we'll need at least one less for the next friend

            # sort all the total items by rlogtime (recent at beginning)
            @items = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @items;

            # cut the list down to what we need.
            @items = splice(@items, 0, $getitems) if (@items > $getitems);
        }

        if (@items == $getitems)
        {
            $lastmax = $items[-1]->{'rlogtime'};

            # stop looping if we know the next friend's newest entry
            # is greater (older) than the oldest one we've already
            # loaded.
            my $nextfr = $get_next_friend->();
            $loop = 0 if ($nextfr && $nextfr->[1] > $lastmax);
        }
    }

    # remove skipped ones
    splice(@items, 0, $skip) if $skip;

    # TODO: KILL! this knows nothing about clusters.
    # return the itemids for them if they wanted them
    if (ref $opts->{'itemids'} eq "ARRAY") {
        @{$opts->{'itemids'}} = map { $_->{'itemid'} } @items;
    }

    # return the itemids grouped by clusters, if callers wants it.
    if (ref $opts->{'idsbycluster'} eq "HASH") {
        foreach (@items) {
            if ($_->{'clusterid'}) {
                push @{$opts->{'idsbycluster'}->{$_->{'clusterid'}}},
                [ $_->{'ownerid'}, $_->{'itemid'} ];
            } else {
                push @{$opts->{'idsbycluster'}->{'0'}}, $_->{'itemid'};
            }
        }
    }

    return @items;
}

# <LJFUNC>
# name: LJ::get_recent_items
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_recent_items
{
    my $dbarg = shift;
    my $opts = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;

    my @items = ();             # what we'll return

    my $userid = $opts->{'userid'}+0;

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    LJ::load_remote($dbs, $remote);
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($dbs, $remoteid);
    }

    my $max_hints = $LJ::MAX_HINTS_LASTN;  # temporary
    my $sort_key = "revttime";

    my $clusterid = $opts->{'clusterid'}+0;
    my $logdb = $dbr;

    if ($clusterid) {
        my $source = $opts->{'clustersource'} eq "slave" ? "slave" : "";
        $logdb = LJ::get_dbh("cluster${clusterid}$source",
                             "cluster$clusterid");  # might have no slave
    }

    # community/friend views need to post by log time, not event time
    $sort_key = "rlogtime" if ($opts->{'order'} eq "logtime" ||
                               $opts->{'friendsview'});

    # 'notafter':
    #   the friends view doesn't want to load things that it knows it
    #   won't be able to use.  if this argument is zero or undefined,
    #   then we'll load everything less than or equal to 1 second from
    #   the end of time.  we don't include the last end of time second
    #   because that's what backdated entries are set to.  (so for one
    #   second at the end of time we'll have a flashback of all those
    #   backdated entries... but then the world explodes and everybody
    #   with 32 bit time_t structs dies)
    my $notafter = $opts->{'notafter'} + 0 || $LJ::EndOfTime - 1;

    my $skip = $opts->{'skip'}+0;
    my $itemshow = $opts->{'itemshow'}+0;
    if ($itemshow > $max_hints) { $itemshow = $max_hints; }
    my $maxskip = $max_hints - $itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }
    my $itemload = $itemshow + $skip;

    # get_friend_items will give us this data structure all at once so
    # we don't have to load each friendof mask one by one, but for
    # a single lastn view, it's okay to just do it once.
    my $gmask_from = $opts->{'gmask_from'};
    unless (ref $gmask_from eq "HASH") {
        $gmask_from = {};
        if ($remote && $remote->{'journaltype'} eq "P") {
            ## then we need to load the group mask for this friend
            $sth = $dbr->prepare("SELECT groupmask FROM friends WHERE userid=$userid ".
                                 "AND friendid=$remoteid");
            $sth->execute;
            my ($mask) = $sth->fetchrow_array;
            $gmask_from->{$userid} = $mask;
        }
    }

    # what mask can the remote user see?
    my $mask = $gmask_from->{$userid} + 0;

    # decide what level of security the remote user can see
    my $secwhere = "";
    if ($userid == $remoteid || $opts->{'viewall'}) {
        # no extra where restrictions... user can see all their own stuff
        # alternatively, if 'viewall' opt flag is set, security is off.
    } elsif ($mask) {
        # can see public or things with them in the mask
        $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $mask != 0))";
    } else {
        # not a friend?  only see public.
        $secwhere = "AND security='public' ";
    }

    # because LJ::get_friend_items needs rlogtime for sorting.
    my $extra_sql;
    if ($opts->{'friendsview'}) {
        if ($clusterid) {
            $extra_sql .= "journalid AS 'ownerid', rlogtime, ";
        } else {
            $extra_sql .= "ownerid, rlogtime, ";
        }
    }

    my $sql;

    if ($clusterid) {
        $sql = ("SELECT jitemid AS 'itemid', posterid, security, replycount, $extra_sql ".
                "DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i ".
                "%l %h %k %H\") AS 'alldatepart', anum ".
                "FROM log2 WHERE journalid=$userid AND $sort_key <= $notafter $secwhere ".
                "ORDER BY journalid, $sort_key ".
                "LIMIT $skip,$itemshow");
    } else {
        # old tables ("cluster 0")
        $sql = ("SELECT itemid, posterid, security, replycount, $extra_sql ".
                "DATE_FORMAT(eventtime, \"%a %W %b %M %y %Y %c %m %e %d %D %p %i ".
                "%l %h %k %H\") AS 'alldatepart' ".
                "FROM log WHERE ownerid=$userid AND $sort_key <= $notafter $secwhere ".
                "ORDER BY ownerid, $sort_key ".
                "LIMIT $skip,$itemshow");
    }

    $sth = $logdb->prepare($sql);
    $sth->execute;
    if ($logdb->err) { die $logdb->errstr; }
    while (my $li = $sth->fetchrow_hashref) {
        push @items, $li;
        push @{$opts->{'itemids'}}, $li->{'itemid'};
    }
    return @items;
}

# <LJFUNC>
# name: LJ::set_userprop
# des: Sets/deletes a userprop by name for a user.
# info: This adds or deletes from the
#       [dbtable[userprop]]/[dbtable[userproplite]] tables.  One
#       crappy thing about this interface is that it doesn't allow
#       a batch of userprops to be updated at once, which is the
#       common thing to do.
# args: dbarg, userid, propname, value
# des-userid: The userid of the user.
# des-propname: The name of the property.
# des-value: The value to set to the property.  If undefined or the
#            empty string, then property is deleted.
# </LJFUNC>
sub set_userprop
{
    my ($dbarg, $userid, $propname, $value) = @_;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    my $p;

    if ($LJ::CACHE_USERPROP{$propname}) {
        $p = $LJ::CACHE_USERPROP{$propname};
    } else {
        my $qpropname = $dbh->quote($propname);
        $userid += 0;
        my $propid;
        my $sth;

        $sth = $dbh->prepare("SELECT upropid, indexed FROM userproplist WHERE name=$qpropname");
        $sth->execute;
        $p = $sth->fetchrow_hashref;
        return unless ($p);
        $LJ::CACHE_USERPROP{$propname} = $p;
    }

    my $table = $p->{'indexed'} ? "userprop" : "userproplite";
    if (defined $value && $value ne "") {
        $value = $dbh->quote($value);
        $dbh->do("REPLACE INTO $table (userid, upropid, value) ".
                 "VALUES ($userid, $p->{'upropid'}, $value)");
    } else {
        $dbh->do("DELETE FROM $table WHERE userid=$userid AND upropid=$p->{'upropid'}");
    }
}

# <LJFUNC>
# name: LJ::register_authaction
# des: Registers a secret to have the user validate.
# info: Some things, like requiring a user to validate their email address, require
#       making up a secret, mailing it to the user, then requiring them to give it
#       back (usually in a URL you make for them) to prove they got it.  This
#       function creates a secret, attaching what it's for and an optional argument.
#       Background maintenance jobs keep track of cleaning up old unvalidated secrets.
# args: dbarg, userid, action, arg?
# des-userid: Userid of user to register authaction for.
# des-action: Action type to register.   Max chars: 50.
# des-arg: Optional argument to attach to the action.  Max chars: 255.
# returns: 0 if there was an error.  Otherwise, a hashref
#          containing keys 'aaid' (the authaction ID) and the 'authcode',
#          a 15 character string of random characters from
#          [func[LJ::make_auth_code]].
# </LJFUNC>
sub register_authaction
{
    my $dbarg = shift;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    my $userid = shift;  $userid += 0;
    my $action = $dbh->quote(shift);
    my $arg1 = $dbh->quote(shift);

    # make the authcode
    my $authcode = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    $dbh->do("INSERT INTO authactions (aaid, userid, datecreate, authcode, action, arg1) ".
             "VALUES (NULL, $userid, NOW(), $qauthcode, $action, $arg1)");

    return 0 if $dbh->err;
    return { 'aaid' => $dbh->{'mysql_insertid'},
             'authcode' => $authcode,
         };
}

# <LJFUNC>
# class: logging
# name: LJ::send_statserv
# des: Sends UDP packet of info to the statistics server.
# returns: Nothing.
# args: cachename, ip, type, url?
# des-cachename: The name to cache this client under. This is can be the
#                logged in username, the value of a guest cookie, or
#                simply "ip" to indicate a cookie-less client.
# des-ip: The dotted quad representing the client's IP address.
# des-type: What type of client this is. "user", "guest" or "ip".
# des-url: An optional URL of what the client hit.
# </LJFUNC>
sub send_statserv
{
    my $user = shift;
    my $ip = shift;
    my $type = shift;
    my $url = shift || "";

    return unless ($LJ::STATSERV);
    # If we don't already have a socket defined, do the startup work.
    unless ($LJ::UDP_SOCKET) {
        my $sock = IO::Socket::INET->new(Proto => 'udp')
                   or print STDERR "Can't create socket: $!\n";
        my $ipaddr = IO::Socket::inet_aton($LJ::STATSERV);
        my $portaddr = IO::Socket::sockaddr_in($LJ::STATSERV_PORT, $ipaddr);
        $LJ::UDP_SOCKET = $sock;
        $LJ::UDP_STATSERV = $portaddr;
    }

    # If we end up with a weird cachename, declare hatred for the
    # IP it came from.
    unless ($user =~ m/\w+/) { $user = "ip"; $type = "ip"; }
    unless (length($user) < 50) { $user = "ip"; $type = "ip"; }

    my $msg = "cmd: $user : $ip : $type";
    if ($url) { $msg .= " : $url"; }

    # This really needs to sound some kind of alarm. If a user can
    # figure out how to execute this code, they can attack the site
    # freely.
    if (length($msg) > 450) {
        print STDERR "statserv message $msg is too long!\n";
    }

    $LJ::UDP_SOCKET->send($msg, 0, $LJ::UDP_STATSERV)
                     or print STDERR "Can't send to statserv: $!\n";

}

# <LJFUNC>
# class: web
# name: LJ::make_cookie
# des: Prepares cookie header lines.
# returns: An array of cookie lines.
# args: name, value, expires, path?, domain?
# des-name: The name of the cookie.
# des-value: The value to set the cookie to.
# des-expires: The time (in seconds) when the cookie is supposed to expire.
#              Set this to 0 to expire when the browser closes. Set it to
#              undef to delete the cookie.
# des-path: The directory path to bind the cookie to.
# des-domain: The domain (or domains) to bind the cookie to.
# </LJFUNC>
sub make_cookie
{
    my ($name, $value, $expires, $path, $domain) = @_;
    my $cookie = "";
    my @cookies = ();

    # let the domain argument be an array ref, so callers can set
    # cookies in both .foo.com and foo.com, for some broken old browsers.
    if ($domain && ref $domain eq "ARRAY") {
        foreach (@$domain) {
            push(@cookies, LJ::make_cookie($name, $value, $expires, $path, $_));
        }
        return;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($expires);
    $year+=1900;

    my @day = qw{Sunday Monday Tuesday Wednesday Thursday Friday Saturday};
    my @month = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    $cookie = sprintf "%s=%s", LJ::eurl($name), LJ::eurl($value);

    # this logic is confusing potentially
    unless (defined $expires && $expires==0) {
        $cookie .= sprintf "; expires=$day[$wday], %02d-$month[$mon]-%04d %02d:%02d:%02d GMT",
                $mday, $year, $hour, $min, $sec;
    }

    $cookie .= "; path=$path" if $path;
    $cookie .= "; domain=$domain" if $domain;
    push(@cookies, $cookie);
    return @cookies;
}


# <LJFUNC>
# class: logging
# name: LJ::statushistory_add
# des: Adds a row to a user's statushistory
# info: See the [dbtable[statushistory]] table.
# returns: boolean; 1 on success, 0 on failure
# args: dbarg, userid, adminid, shtype, notes?
# des-userid: The user getting acted on.
# des-adminid: The site admin doing the action.
# des-shtype: The status history type code.
# des-notes: Optional notes associated with this action.
# </LJFUNC>
sub statushistory_add
{
    my $dbarg = shift;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    my $userid = shift;  $userid += 0;
    my $actid  = shift;  $actid  += 0;

    my $qshtype = $dbh->quote(shift);
    my $qnotes  = $dbh->quote(shift);

    $dbh->do("INSERT INTO statushistory (userid, adminid, shtype, notes) ".
             "VALUES ($userid, $actid, $qshtype, $qnotes)");
    return $dbh->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::make_link
# des: Takes a group of key=value pairs to append to a url
# returns: The finished url
# args: url, vars
# des-url: A string with the URL to append to.  The URL
#          shouldn't have a question mark in it.
# des-vars: A hashref of the key=value pairs to append with.
# </LJFUNC>
sub make_link
{
    my $url = shift;
    my $vars = shift;
    my $append = "?";
    foreach (keys %$vars) {
        next if ($vars->{$_} eq "");
        $url .= "${append}${_}=$vars->{$_}";
        $append = "&";
    }
    return $url;
}

# <LJFUNC>
# class: time
# name: LJ::ago_text
# des: Converts integer seconds to English time span
# info: Turns a number of seconds into the largest possible unit of
#       time. "2 weeks", "4 days", or "20 hours".
# returns: A string with the number of largest units found
# args: secondsold
# des-secondsold: The number of seconds from now something was made.
# </LJFUNC>
sub ago_text
{
    my $secondsold = shift;
    return "Never." unless ($secondsold);
    my $num;
    my $unit;
    if ($secondsold > 60*60*24*7) {
        $num = int($secondsold / (60*60*24*7));
        $unit = "week";
    } elsif ($secondsold > 60*60*24) {
        $num = int($secondsold / (60*60*24));
        $unit = "day";
    } elsif ($secondsold > 60*60) {
        $num = int($secondsold / (60*60));
        $unit = "hour";
    } elsif ($secondsold > 60) {
        $num = int($secondsold / (60));
        $unit = "minute";
    } else {
        $num = $secondsold;
        $unit = "second";
    }
    return "$num $unit" . ($num==1?"":"s") . " ago";
}

# <LJFUNC>
# class: component
# name: LJ::auth_fields
# des: Makes a login form.
# info: Returns a form for either submitting username/password to a script or
#       entering a new username/password.
# returns: The built form
# args: form, opts?
# des-form: The hash of form information, which is used to determine whether to
#           get the current login info and display a concise form, or to display
#           a login form.
# des-opts: hashref containing 'user' key to force (finds/makes the hpassword)
# </LJFUNC>
sub auth_fields
{
    my $form = shift;
    my $opts = shift;

    my $remote = LJ::get_remote_noauth();
    my $ret = "";
    if ((!$form->{'altlogin'} && $remote) || $opts->{'user'})
    {
        my $hpass;
        my $luser = $opts->{'user'} || $remote->{'user'};
        if ($opts->{'user'}) {
            $hpass = $form->{'hpassword'} || LJ::hash_password($form->{'password'});
        } elsif ($remote && $BMLClient::COOKIE{"ljhpass"} =~ /^$luser:(.+)/) {
            $hpass = $1;
        }

        my $alturl = $ENV{'REQUEST_URI'};
        $alturl .= ($alturl =~ /\?/) ? "&amp;" : "?";
        $alturl .= "altlogin=1";

        $ret .= "<tr align='left'><td colspan='2' align='left'>You are currently logged in as <b>$luser</b>.";
        $ret .= "<br />If this is not you, <a href='$alturl'>click here</a>.\n"
            unless $opts->{'noalt'};
        $ret .= "<input type='hidden' name='user' value='$luser'>\n";
        $ret .= "<input type='hidden' name='hpassword' value='$hpass'><br />&nbsp;\n";
        $ret .= "</td></tr>\n";
    } else {
        $ret .= "<tr align='left'><td>Username:</td><td align='left'><input type='text' name='user' size='15' maxlength='15' value='";
        my $user = $form->{'user'};
        unless ($user || $ENV{'QUERY_STRING'} =~ /=/) { $user=$ENV{'QUERY_STRING'}; }
        $ret .= BMLUtil::escapeall($user) unless ($form->{'altlogin'});
        $ret .= "' /></td></tr>\n";
        $ret .= "<tr><td>Password:</td><td align='left'>\n";
        my $epass = LJ::ehtml($form->{'password'});
        $ret .= "<input type='password' name='password' size='15' maxlength='30' value='$epass' />";
        $ret .= "</td></tr>\n";
    }
    return $ret;
}

# <LJFUNC>
# class: component
# name: LJ::auth_fields_2
# des: Makes a login form.
# info: Like [func[LJ::auth_fields]], with a lot more functionality.  Creates the
#       HTML for a login box if user not logged in. Creates a drop-down
#       selection box of possible journals to switch to if user is logged in.
# returns: The resultant HTML form box.
# args: form, opts
# des-form: Form results from the previous page.
# des-opts: Journal/password options for changing the login box.
# </LJFUNC>
sub auth_fields_2
{
    my $dbs = shift;
    my $form = shift;
    my $opts = shift;
    my $remote = LJ::get_remote($dbs);
    my $ret = "";

    # text box mode
    if ($form->{'authas'} eq "(other)" || $form->{'altlogin'} ||
        $form->{'user'} || ! $remote)
    {
        $ret .= "<tr><td align='right'><u>U</u>sername:</td><td align='left'><input type=\"text\" name='user' size='15' maxlength='15' accesskey='u' value=\"";
        my $user = $form->{'user'};
        unless ($user || $ENV{'QUERY_STRING'} =~ /=/) { $user=$ENV{'QUERY_STRING'}; }
        $ret .= BMLUtil::escapeall($user) unless ($form->{'altlogin'});
        $ret .= "\" /></td></tr>\n";
        $ret .= "<tr><td align='right'><u>P</u>assword:</td><td align='left'>\n";
        $ret .= "<input type='password' name='password' size='15' maxlength='30' accesskey='p' value=\"" .
            LJ::ehtml($opts->{'password'}) . "\" />";
        $ret .= "</td></tr>\n";
        return $ret;
    }

    # logged in mode
    $ret .= "<tr><td align='right'><u>U</u>sername:</td><td align='left'>";

    my $alturl = LJ::self_link($form, { 'altlogin' => 1 });
    my @shared = ($remote->{'user'});

    my $sopts = {};
    $sopts->{'notshared'} = 1 unless $opts->{'shared'};
    $sopts->{'getother'} = $opts->{'getother'};

    $ret .= LJ::make_shared_select($dbs, $remote, $form, $sopts);

    if ($sopts->{'getother'}) {
        my $alturl = LJ::self_link($form, { 'altlogin' => 1 });
        $ret .= "&nbsp;(<a href='$alturl'>Other</a>)";
    }

    $ret .= "</td></tr>\n";
    return $ret;
}

# <LJFUNC>
# class: component
# name: LJ::make_shared_select
# des: Creates a list of shared journals a user has access to
#      for insertion into a drop-down menu.
# returns: The HTML for the options menu.
# args: u, form, opts
# des-form: The form hash from the previous page.
# des-opts: A hash of options to change the types of selections shown.
# </LJFUNC>
sub make_shared_select
{
    my ($dbs, $u, $form, $opts) = @_;

    my %u2k;
    $u2k{$u->{'user'}} = "(remote)";

    my @choices = ("(remote)", $u->{'user'});
    unless ($opts->{'notshared'}) {
        foreach (LJ::get_shared_journals($dbs, $u)) {
            push @choices, $_, $_;
            $u2k{$_} = $_;
        }
    }
    unless ($opts->{'getother'}) {
        push @choices, "(other)", "Other...";
    }

    if (@choices > 2) {
        my $sel;
        if ($form->{'user'}) {
            $sel = $u2k{$form->{'user'}} || "(other)";
        } else {
            $sel = $form->{'authas'};
        }
        return LJ::html_select({
            'name' => 'authas',
            'raw' => "accesskey='u'",
            'selected' => $sel,
        }, @choices);
    } else {
        return "<b>$u->{'user'}</b>";
    }
}

# <LJFUNC>
# name: LJ::get_shared_journals
# des: Gets an array of shared journals a user has access to.
# returns: An array of shared journals.
# args: dbs, u
# </LJFUNC>
sub get_shared_journals
{
    my $dbs = shift;
    my $u = shift;
    LJ::load_user_privs($dbs, $u, "sharedjournal");
    return sort keys %{$u->{'_priv'}->{'sharedjournal'}};
}

# <LJFUNC>
# name: LJ::get_effective_user
# des: Given a set of input, will return the effective user to process as.
# info: Is passed a reference to a form hash, a remote hash reference, a
#       reference to an error variable, and a reference to a user hash to
#       possibly fill. Given the form input, it will authenticate and return
#       the user (logged in user, a community, other user) that the remote
#       user requested to do an action with.
# returns: The user to process as.
# args: dbs, opts
# des-opts: A hash of options to pass.
# </LJFUNC>
sub get_effective_user
{
    my $dbs = shift;
    my $opts = shift;
    my $f = $opts->{'form'};
    my $refu = $opts->{'out_u'};
    my $referr = $opts->{'out_err'};
    my $remote = $opts->{'remote'};

    $$referr = "";

    # presence of 'altlogin' means user is probably logged in but
    # wants to act as somebody else, so ignore their cookie and just
    # fail right away, which'll cause the form to be loaded where they
    # can enter manually a username.
    if ($f->{'altlogin'}) { return ""; }

    # this means the same, and is used by LJ::make_shared_select:
    if ($f->{'authas'} eq "(other)") { return ""; }

    # an explicit 'user' argument overrides the remote setting.  if
    # the password is correct, the user they requested is the
    # effective one, else we have no effective yet.
    if ($f->{'user'}) {
        my $u = LJ::load_user($dbs, $f->{'user'});
        unless ($u) {
            $$referr = "Invalid user.";
            return;
        }

        # if password present, check it.
        if ($f->{'password'} || $f->{'hpassword'}) {
            if (LJ::auth_okay($u, $f->{'password'}, $f->{'hpassword'}, $u->{'password'})) {
                $$refu = $u;
                return $f->{'user'};
            } else {
                $$referr = "Invalid password.";
                return;
            }
        }

        # otherwise don't check it and return nothing (to prevent the
        # remote setting from taking place... this forces the
        # user/password boxes to appear)
        return;
    }

    # not logged in?
    return unless $remote;

    # logged in. use self identity unless they're requesting to act as
    # a community.
    return $remote->{'user'}
    unless ($f->{'authas'} && $f->{'authas'} ne "(remote)");

    # if they have the privs, let them be that community
    return $f->{'authas'}
    if (LJ::check_priv($dbs, $remote, "sharedjournal", $f->{'authas'}));

    # else, complain.
    $$referr = "Invalid privileges to act as requested community.";
    return;
}

# <LJFUNC>
# class: web
# name: LJ::self_link
# des: Takes the URI of the current page, and adds the current form data
#      to the url, then adds any additional data to the url.
# returns: scalar; the full url
# args: form, newvars
# des-form: A hashref of the form information from the page.
# des-newvars: A hashref of information to add/override to the link.
# </LJFUNC>
sub self_link
{
    my $form = shift;
    my $newvars = shift;
    my $link = $ENV{'REQUEST_URI'};
    $link =~ s/\?.+//;
    $link .= "?";
    foreach (keys %$newvars) {
        if (! exists $form->{$_}) { $form->{$_} = ""; }
    }
    foreach (sort keys %$form) {
        if (defined $newvars->{$_} && ! $newvars->{$_}) { next; }
        my $val = $newvars->{$_} || $form->{$_};
        next unless $val;
        $link .= LJ::eurl($_) . "=" . LJ::eurl($val) . "&";
    }
    chop $link;
    return $link;
}

# <LJFUNC>
# class: web
# name: LJ::get_query_string
# des: Returns the query string, which can be in a number of spots
#      depending on the webserver & configuration, sadly.
# returns: String; query string.
# </LJFUNC>
sub get_query_string
{
    my $q = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
    if ($q eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
        $q = $1;
    }
    return $q;
}

# <LJFUNC>
# class: web
# name: LJ::get_form_data
# des: Loads a hashref with form data from a GET or POST request.
# args: hashref, type?
# des-hashref: Hashref to populate with form data.
# des-type: If "GET", will ignore POST data.
# </LJFUNC>
sub get_form_data
{
    my $hashref = shift;
    my $type = shift;
    my $buffer;

    if ($ENV{'REQUEST_METHOD'} eq 'POST' && $type ne "GET") {
        read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    } else {
        $buffer = $ENV{'QUERY_STRING'} || $ENV{'REDIRECT_QUERY_STRING'};
        if ($buffer eq "" && $ENV{'REQUEST_URI'} =~ /\?(.+)/) {
            $buffer = $1;
        }
    }

    # Split the name-value pairs
    LJ::decode_url_string($buffer, $hashref);
}

# <LJFUNC>
# name: LJ::is_valid_authaction
# des: Validates a shared secret (authid/authcode pair)
# info: See [func[LJ::register_authaction]].
# returns: Hashref of authaction row from database.
# args: dbarg, aaid, auth
# des-aaid: Integer; the authaction ID.
# des-auth: String; the auth string. (random chars the client already got)
# </LJFUNC>
sub is_valid_authaction
{
    my $dbarg = shift;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    # TODO: make this use slave if available (low usage/priority)
    my ($aaid, $auth) = map { $dbh->quote($_) } @_;
    my $sth = $dbh->prepare("SELECT aaid, userid, datecreate, authcode, action, arg1 FROM authactions WHERE aaid=$aaid AND authcode=$auth");
    $sth->execute;
    return $sth->fetchrow_hashref;
}

# <LJFUNC>
# class: s1
# name: LJ::fill_var_props
# args: vars, key, hashref
# des: S1 utility function to interpolate %%variables%% in a variable.  If
#      a modifier is given like %%foo:var%%, then [func[LJ::fvp_transform]]
#      is called.
# des-vars: hashref with keys being S1 vars
# des-key: the variable in the vars hashref we're expanding
# des-hashref: hashref of values that could interpolate.
# returns: Expanded string.
# </LJFUNC>
sub fill_var_props
{
    my ($vars, $key, $hashref) = @_;
    my $data = $vars->{$key};
    $data =~ s/%%(?:([\w:]+:))?(\S+?)%%/$1 ? LJ::fvp_transform(lc($1), $vars, $hashref, $2) : $hashref->{$2}/eg;
    return $data;
}

# <LJFUNC>
# class: s1
# name: LJ::fvp_transform
# des: Called from [func[LJ::fill_var_props]] to do trasformations.
# args: transform, vars, hashref, attr
# des-transform: The transformation type.
# des-vars: hashref with keys being S1 vars
# des-hashref: hashref of values that could interpolate. (see
#              [func[LJ::fill_var_props]])
# des-attr: the attribute name that's being interpolated.
# returns: Transformed interpolated variable.
# </LJFUNC>
sub fvp_transform
{
    my ($transform, $vars, $hashref, $attr) = @_;
    my $ret = $hashref->{$attr};
    while ($transform =~ s/(\w+):$//) {
        my $trans = $1;
        if ($trans eq "ue") {
            $ret = LJ::eurl($ret);
        }
        elsif ($trans eq "xe") {
            $ret = LJ::exml($ret);
        }
        elsif ($trans eq "lc") {
            $ret = lc($ret);
        }
        elsif ($trans eq "uc") {
            $ret = uc($ret);
        }
        elsif ($trans eq "color") {
            $ret = $vars->{"color-$attr"};
        }
        elsif ($trans eq "cons") {
            if ($attr eq "siteroot") { return $LJ::SITEROOT; }
            if ($attr eq "sitename") { return $LJ::SITENAME; }
            if ($attr eq "img") { return $LJ::IMGPREFIX; }
        }
    }
    return $ret;
}

# <LJFUNC>
# name: LJ::get_mood_picture
# des: Loads a mood icon hashref given a themeid and moodid.
# args: themeid, moodid, ref
# des-themeid: Integer; mood themeid.
# des-moodid: Integer; mood id.
# des-ref: Hashref to load mood icon data into.
# returns: Boolean; 1 on success, 0 otherwise.
# </LJFUNC>
sub get_mood_picture
{
    my ($themeid, $moodid, $ref) = @_;
    do
    {
        if ($LJ::CACHE_MOOD_THEME{$themeid}->{$moodid}) {
            %{$ref} = %{$LJ::CACHE_MOOD_THEME{$themeid}->{$moodid}};
            if ($ref->{'pic'} =~ m!^/!) {
                $ref->{'pic'} =~ s!^/img!!;
                $ref->{'pic'} = $LJ::IMGPREFIX . $ref->{'pic'};
            }
            $ref->{'moodid'} = $moodid;
            return 1;
        } else {
            $moodid = $LJ::CACHE_MOODS{$moodid}->{'parent'};
        }
    }
    while ($moodid);
    return 0;
}


# <LJFUNC>
# class: s1
# name: LJ::prepare_currents
# des: do all the current music/mood/weather/whatever stuff.  only used by ljviews.pl.
# args: dbarg, args
# des-args: hashref with keys: 'props' (a hashref with itemid keys), 'vars' hashref with
#           keys being S1 variables.
# </LJFUNC>
sub prepare_currents
{
    my $dbarg = shift;
    my $args = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $datakey = $args->{'datakey'} || $args->{'itemid'}; # new || old

    my %currents = ();
    my $val;
    if ($val = $args->{'props'}->{$datakey}->{'current_music'}) {
        $currents{'Music'} = $val;
    }
    if ($val = $args->{'props'}->{$datakey}->{'current_mood'}) {
        $currents{'Mood'} = $val;
    }
    if ($val = $args->{'props'}->{$datakey}->{'current_moodid'}) {
        my $theme = $args->{'user'}->{'moodthemeid'};
        LJ::load_mood_theme($dbs, $theme);
        my %pic;
        if (LJ::get_mood_picture($theme, $val, \%pic)) {
            $currents{'Mood'} = "<img src=\"$pic{'pic'}\" align='absmiddle' width='$pic{'w'}' ".
                "height='$pic{'h'}' vspace='1'> $LJ::CACHE_MOODS{$val}->{'name'}";
        } else {
            $currents{'Mood'} = $LJ::CACHE_MOODS{$val}->{'name'};
        }
    }
    if (%currents) {
        if ($args->{'vars'}->{$args->{'prefix'}.'_CURRENTS'})
        {
            ### PREFIX_CURRENTS is defined, so use the correct style vars

            my $fvp = { 'currents' => "" };
            foreach (sort keys %currents) {
                $fvp->{'currents'} .= LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENT', {
                    'what' => $_,
                    'value' => $currents{$_},
                });
            }
            $args->{'event'}->{'currents'} =
                LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENTS', $fvp);
        } else
        {
            ### PREFIX_CURRENTS is not defined, so just add to %%events%%
            $args->{'event'}->{'event'} .= "<br />&nbsp;";
            foreach (sort keys %currents) {
                $args->{'event'}->{'event'} .= "<br /><b>Current $_</b>: " . $currents{$_} . "\n";
            }
        }
    }
}


# <LJFUNC>
# class: time
# name: LJ::http_to_time
# des: Converts HTTP date to Unix time.
# info: Wrapper around HTTP::Date::str2time.
#       See also [func[LJ::time_to_http]].
# args: string
# des-string: HTTP Date.  See RFC 2616 for format.
# returns: integer; Unix time.
# </LJFUNC>
sub http_to_time {
    my $string = shift;
    return HTTP::Date::str2time($string);
}

# <LJFUNC>
# class: time
# name: LJ::time_to_http
# des: Converts a Unix time to an HTTP date.
# info: Wrapper around HTTP::Date::time2str to make an
#       HTTP date (RFC 1123 format)  See also [func[LJ::http_to_time]].
# args: time
# des-time: Integer; Unix time.
# returns: String; RFC 1123 date.
# </LJFUNC>
sub time_to_http {
    my $time = shift;
    return HTTP::Date::time2str($time);
}

# <LJFUNC>
# class: component
# name: LJ::ljuser
# des: Make link to userinfo/journal of user.
# info: Returns the HTML for an userinfo/journal link pair for a given user
#       name, just like LJUSER does in BML.  But files like cleanhtml.pl
#       and ljpoll.pl need to do that too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to.
# des-opts: Optional hashref to control output.  Currently only recognized key
#           is 'full' which when true causes a link to the mode=full userinfo.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser
{
    my $user = shift;
    my $opts = shift;
    my $andfull = $opts->{'full'} ? "&amp;mode=full" : "";
    return "<a href=\"$LJ::SITEROOT/userinfo.bml?user=$user$andfull\"><img src=\"$LJ::IMGPREFIX/userinfo.gif\" width=\"17\" height=\"17\" align=\"absmiddle\" border=\"0\"></a><b><a href=\"$LJ::SITEROOT/users/$user/\">$user</a></b>";
}

# <LJFUNC>
# name: LJ::get_urls
# des: Returns a list of all referenced URLs from a string
# args: text
# des-text: Text to extra URLs from
# returns: list of URLs
# </LJFUNC>
sub get_urls
{
    my $text = shift;
    my @urls;
    while ($text =~ s!http://[^\s\"\'\<\>]+!!) {
        push @urls, $&;
    }
    return @urls;
}

# <LJFUNC>
# name: LJ::record_meme
# des: Records a URL reference from a journal entry to the meme table.
# args: dbarg, url, posterid, itemid, journalid?
# des-url: URL to log
# des-posterid: Userid of person posting
# des-itemid: Itemid URL appears in.  For non-clustered users, this is just
#             the itemid.  For clustered users, this is the display itemid,
#             which is the jitemid*256+anum from the [dbtable[log2]] table.
# des-journalid: Optional, journal id of item, if item is clustered.  Otherwise
#                this should be zero or undef.
# </LJFUNC>
sub record_meme
{
    my ($dbarg, $url, $posterid, $itemid, $jid) = @_;
    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};

    $url =~ s!/$!!;  # strip / at end
    LJ::run_hooks("canonicalize_url", \$url);

    # canonicalize_url hook might just erase it, so
    # we don't want to record it.
    return unless $url;

    my $qurl = $dbh->quote($url);
    $posterid += 0;
    $itemid += 0;
    $jid += 0;
    LJ::query_buffer_add($dbs, "meme",
                         "REPLACE INTO meme (url, posterid, journalid, itemid) " .
                         "VALUES ($qurl, $posterid, $jid, $itemid)");
}

# <LJFUNC>
# name: LJ::name_caps
# des: Given a user's capability class bit mask, returns a
#      site-specific string representing the capability class name.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub name_caps
{
    return undef unless LJ::are_hooks("name_caps");
    my $caps = shift;
    my @r = LJ::run_hooks("name_caps", $caps);
    return $r[0]->[0];
}

# <LJFUNC>
# name: LJ::name_caps_short
# des: Given a user's capability class bit mask, returns a
#      site-specific short string code.
# args: caps
# des-caps: 16 bit capability bitmask
# </LJFUNC>
sub name_caps_short
{
    return undef unless LJ::are_hooks("name_caps_short");
    my $caps = shift;
    my @r = LJ::run_hooks("name_caps_short", $caps);
    return $r[0]->[0];
}

# <LJFUNC>
# name: LJ::get_cap
# des: Given a user object or capability class bit mask and a capability/limit name,
#      returns the maximum value allowed for given user or class, considering
#      all the limits in each class the user is a part of.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in doc/capabilities.txt
# </LJFUNC>
sub get_cap
{
    my $caps = shift;   # capability bitmask (16 bits), or user object
    my $cname = shift;  # capability limit name
    if (! defined $caps) { $caps = 0; }
    elsif (ref $caps eq "HASH") { $caps = $caps->{'caps'}; }
    my $max = undef;
    foreach my $bit (keys %LJ::CAP) {
        next unless ($caps & (1 << $bit));
        my $v = $LJ::CAP{$bit}->{$cname};
        next unless (defined $v);
        next if (defined $max && $max > $v);
        $max = $v;
    }
    return defined $max ? $max : $LJ::CAP_DEF{$cname};
}

# <LJFUNC>
# name: LJ::get_cap_min
# des: Just like [func[LJ::get_cap]], but returns the minimum value.
#      Although it might not make sense at first, some things are
#      better when they're low, like the minimum amount of time
#      a user might have to wait between getting updates or being
#      allowed to refresh a page.
# args: u_cap, capname
# des-u_cap: 16 bit capability bitmask or a user object from which the
#            bitmask could be obtained
# des-capname: the name of a limit, defined in doc/capabilities.txt
# </LJFUNC>
sub get_cap_min
{
    my $caps = shift;   # capability bitmask (16 bits), or user object
    my $cname = shift;  # capability name
    if (! defined $caps) { $caps = 0; }
    elsif (ref $caps eq "HASH") { $caps = $caps->{'caps'}; }
    my $min = undef;
    foreach my $bit (keys %LJ::CAP) {
        next unless ($caps & (1 << $bit));
        my $v = $LJ::CAP{$bit}->{$cname};
        next unless (defined $v);
        next if (defined $min && $min < $v);
        $min = $v;
    }
    return defined $min ? $min : $LJ::CAP_DEF{$cname};
}

# <LJFUNC>
# name: LJ::help_icon
# des: Returns BML to show a help link/icon given a help topic, or nothing
#      if the site hasn't defined a URL for that topic.  Optional arguments
#      include HTML/BML to place before and after the link/icon, should it
#      be returned.
# args: topic, pre?, post?
# des-topic: Help topic key.  See doc/ljconfig.pl.txt for examples.
# des-pre: HTML/BML to place before the help icon.
# des-post: HTML/BML to place after the help icon.
# </LJFUNC>
sub help_icon
{
    my $topic = shift;
    my $pre = shift;
    my $post = shift;
    return "" unless (defined $LJ::HELPURL{$topic});
    return "$pre(=HELP $LJ::HELPURL{$topic} HELP=)$post";
}

# <LJFUNC>
# name: LJ::are_hooks
# des: Returns true if the site has one or more hooks installed for
#      the given hookname.
# args: hookname
# </LJFUNC>
sub are_hooks
{
    my $hookname = shift;
    return defined $LJ::HOOKS{$hookname};
}

# <LJFUNC>
# name: LJ::clear_hooks
# des: Removes all hooks.
# </LJFUNC>
sub clear_hooks
{
    %LJ::HOOKS = ();
}

# <LJFUNC>
# name: LJ::run_hooks
# des: Runs all the site-specific hooks of the given name.
# returns: list of arrayrefs, one for each hook ran, their
#          contents being their own return values.
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hooks
{
    my $hookname = shift;
    my @args = shift;
    my @ret;
    foreach my $hook (@{$LJ::HOOKS{$hookname}}) {
        push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::register_hook
# des: Installs a site-specific hook.
# info: Installing multiple hooks per hookname is valid.
#       They're run later in the order they're registered.
# args: hookname, subref
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_hook
{
    my $hookname = shift;
    my $subref = shift;
    push @{$LJ::HOOKS{$hookname}}, $subref;
}

# <LJFUNC>
# name: LJ::make_auth_code
# des: Makes a random string of characters of a given length.
# returns: string of random characters, from an alphabet of 30
#          letters & numbers which aren't easily confused.
# args: length
# des-length: length of auth code to return
# </LJFUNC>
sub make_auth_code
{
    my $length = shift;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    my $auth;
    for (1..$length) { $auth .= substr($digits, int(rand(30)), 1); }
    return $auth;
}

# <LJFUNC>
# name: LJ::acid_encode
# des: Given a decimal number, returns base 30 encoding
#      using an alphabet of letters & numbers that are
#      not easily mistaken for each other.
# returns: Base 30 encoding, alwyas 7 characters long.
# args: number
# des-number: Number to encode in base 30.
# </LJFUNC>
sub acid_encode
{
    my $num = shift;
    my $acid = "";
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    while ($num) {
        my $dig = $num % 30;
        $acid = substr($digits, $dig, 1) . $acid;
        $num = ($num - $dig) / 30;
    }
    return ("a"x(7-length($acid)) . $acid);
}

# <LJFUNC>
# name: LJ::acid_decode
# des: Given an acid encoding from [func[LJ::acid_encode]],
#      returns the original decimal number.
# returns: Integer.
# args: acid
# des-acid: base 30 number from [func[LJ::acid_encode]].
# </LJFUNC>
sub acid_decode
{
    my $acid = shift;
    $acid = lc($acid);
    my %val;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    for (0..30) { $val{substr($digits,$_,1)} = $_; }
    my $num = 0;
    my $place = 0;
    while ($acid) {
        return 0 unless ($acid =~ s/[$digits]$//o);
        $num += $val{$&} * (30 ** $place++);
    }
    return $num;
}

# <LJFUNC>
# name: LJ::acct_code_generate
# des: Creates an invitation code from an optional userid
#      for use by anybody.
# returns: Account/Invite code.
# args: dbarg, userid?
# des-userid: Userid to make the invitation code from,
#             else the code will be from userid 0 (system)
# </LJFUNC>
sub acct_code_generate
{
    my $dbarg = shift;
    my $userid = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $auth = LJ::make_auth_code(5);
    $userid = int($userid);
    $dbh->do("INSERT INTO acctcode (acid, userid, rcptid, auth) ".
             "VALUES (NULL, $userid, 0, \"$auth\")");
    my $acid = $dbh->{'mysql_insertid'};
    return undef unless $acid;
    return acct_code_encode($acid, $auth);
}

# <LJFUNC>
# name: LJ::acct_code_encode
# des: Given an account ID integer and a 5 digit auth code, returns
#      a 12 digit account code.
# returns: 12 digit account code.
# args: acid, auth
# des-acid: account ID, a 4 byte unsigned integer
# des-auth: 5 random characters from base 30 alphabet.
# </LJFUNC>
sub acct_code_encode
{
    my $acid = shift;
    my $auth = shift;
    return lc($auth) . acid_encode($acid);
}

# <LJFUNC>
# name: LJ::acct_code_decode
# des: Breaks an account code down into its two parts
# returns: list of (account ID, auth code)
# args: code
# des-code: 12 digit account code
# </LJFUNC>
sub acct_code_decode
{
    my $code = shift;
    return (acid_decode(substr($code, 5, 7)), lc(substr($code, 0, 5)));
}

# <LJFUNC>
# name: LJ::acct_code_check
# des: Checks the validity of a given account code
# returns: boolean; 0 on failure, 1 on validity. sets $$err on failure.
# args: dbarg, code, err?, userid?
# des-code: account code to check
# des-err: optional scalar ref to put error message into on failure
# des-userid: optional userid which is allowed in the rcptid field,
#             to allow for htdocs/create.bml case when people double
#             click the submit button.
# </LJFUNC>
sub acct_code_check
{
    my $dbarg = shift;
    my $code = shift;
    my $err = shift;     # optional; scalar ref
    my $userid = shift;  # optional; acceptable userid (double-click proof)

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    unless (length($code) == 12) {
        $$err = "Malformed code; not 12 characters.";
        return 0;
    }

    my ($acid, $auth) = acct_code_decode($code);

    # are we sure this is what the master has?  if we have a slave, could be behind.
    my $definitive = ! $dbs->{'has_slave'};

    # try to load from slave
    my $ac = $dbr->selectrow_hashref("SELECT userid, rcptid, auth FROM acctcode WHERE acid=$acid");

    # if we loaded something, and that code's used, it must be what master has
    if ($ac && $ac->{'rcptid'}) {
        $definitive = 1;
    }

    # unless we're sure we have a clean record, load from master:
    unless ($definitive) {
        $ac = $dbh->selectrow_hashref("SELECT userid, rcptid, auth FROM acctcode WHERE acid=$acid");
    }

    unless ($ac && $ac->{'auth'} eq $auth) {
        $$err = "Invalid account code.";
        return 0;
    }

    if ($ac->{'rcptid'} && $ac->{'rcptid'} != $userid) {
        $$err = "This code has already been used.";
        return 0;
    }

    # is the journal this code came from suspended?
    my $statusvis = LJ::dbs_selectrow_array($dbs, "SELECT statusvis FROM user ".
                                            "WHERE userid=$ac->{'userid'}");
    if ($statusvis eq "S") {
        $$err = "Code belongs to a suspended account.";
        return 0;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::load_mood_theme
# des: Loads and caches a mood theme, or returns immediately if already loaded.
# args: dbarg, themeid
# des-themeid: the mood theme ID to load
# </LJFUNC>
sub load_mood_theme
{
    my $dbarg = shift;
    my $themeid = shift;
    return if ($LJ::CACHE_MOOD_THEME{$themeid});

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    $themeid += 0;
    my $sth = $dbr->prepare("SELECT moodid, picurl, width, height FROM moodthemedata WHERE moodthemeid=$themeid");
    $sth->execute;
    while (my ($id, $pic, $w, $h) = $sth->fetchrow_array) {
        $LJ::CACHE_MOOD_THEME{$themeid}->{$id} = { 'pic' => $pic, 'w' => $w, 'h' => $h };
    }
    $sth->finish;
}

# <LJFUNC>
# name: LJ::load_props
# des: Loads and caches one or more of the various *proplist tables:
#      logproplist, talkproplist, and userproplist, which describe
#      the various meta-data that can be stored on log (journal) items,
#      comments, and users, respectively.
# args: dbarg, table*
# des-table: a list of tables' proplists to load.  can be one of
#            "log", "talk", or "user".
# </LJFUNC>
sub load_props
{
    my $dbarg = shift;
    my @tables = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my %keyname = qw(log  propid
                     talk tpropid
                     user upropid);

    foreach my $t (@tables) {
        next unless defined $keyname{$t};
        next if (defined $LJ::CACHE_PROP{$t});
        my $sth = $dbr->prepare("SELECT * FROM ${t}proplist");
        $sth->execute;
        while (my $p = $sth->fetchrow_hashref) {
            $p->{'id'} = $p->{$keyname{$t}};
            $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
            $LJ::CACHE_PROPID{$t}->{$p->{'id'}} = $p;
        }
        $sth->finish;
    }
}

# <LJFUNC>
# name: LJ::get_prop
# des: This is used after [func[LJ::load_props]] is called to retrieve
#      a hashref of a row from the given tablename's proplist table.
#      One difference from getting it straight from the database is
#      that the 'id' key is always present, as a copy of the real
#      proplist unique id for that table.
# args: table, name
# returns: hashref of proplist row from db
# des-table: the tables to get a proplist hashref from.  can be one of
#            "log", "talk", or "user".
# des-name: the name of the prop to get the hashref of.
# </LJFUNC>
sub get_prop
{
    my $table = shift;
    my $name = shift;
    return 0 unless defined $LJ::CACHE_PROP{$table};
    return $LJ::CACHE_PROP{$table}->{$name};
}

# <LJFUNC>
# name: LJ::load_codes
# des: Populates hashrefs with lookup data from the database or from memory,
#      if already loaded in the past.  Examples of such lookup data include
#      state codes, country codes, color name/value mappings, etc.
# args: dbarg, whatwhere
# des-whatwhere: a hashref with keys being the code types you want to load
#                and their associated values being hashrefs to where you
#                want that data to be populated.
# </LJFUNC>
sub load_codes
{
    my $dbarg = shift;
    my $req = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    foreach my $type (keys %{$req})
    {
        unless ($LJ::CACHE_CODES{$type})
        {
            $LJ::CACHE_CODES{$type} = [];
            my $qtype = $dbr->quote($type);
            my $sth = $dbr->prepare("SELECT code, item FROM codes WHERE type=$qtype ORDER BY sortorder");
            $sth->execute;
            while (my ($code, $item) = $sth->fetchrow_array)
            {
                push @{$LJ::CACHE_CODES{$type}}, [ $code, $item ];
            }
        }

        foreach my $it (@{$LJ::CACHE_CODES{$type}})
        {
            if (ref $req->{$type} eq "HASH") {
                $req->{$type}->{$it->[0]} = $it->[1];
            } elsif (ref $req->{$type} eq "ARRAY") {
                push @{$req->{$type}}, { 'code' => $it->[0], 'item' => $it->[1] };
            }
        }
    }
}

# <LJFUNC>
# name: LJ::img
# des: Returns an HTML &lt;img&gt; or &lt;input&gt; tag to an named image
#      code, which each site may define with a different image file with
#      its own dimensions.  This prevents hard-coding filenames & sizes
#      into the source.  The real image data is stored in LJ::Img, which
#      has default values provided in cgi-bin/imageconf.pl but can be
#      overridden in cgi-bin/ljconfig.pl.
# args: imagecode, type?, attrs?
# des-imagecode: The unique string key to reference the image.  Not a filename,
#                but the purpose or location of the image.
# des-type: By default, the tag returned is an &lt;img&gt; tag, but if 'type'
#           is "input", then an input tag is returned.
# des-attrs: Optional hashref of other attributes.  If this isn't a hashref,
#            then it's assumed to be a scalar for the 'name' attribute for
#            input controls.
# </LJFUNC>
sub img
{
    my $ic = shift;
    my $type = shift;  # either "" or "input"
    my $attr = shift;

    my $attrs;
    if ($attr) {
        if (ref $attr eq "HASH") {
            foreach (keys %$attr) {
                $attrs .= " $_=\"" . LJ::ehtml($attr->{$_}) . "\"";
            }
        } else {
            $attrs = " name=\"$attr\"";
        }
    }

    my $i = $LJ::Img::img{$ic};
    if ($type eq "") {
        return "<img src=\"$LJ::IMGPREFIX$i->{'src'}\" width=\"$i->{'width'}\" ".
            "height=\"$i->{'height'}\" alt=\"$i->{'alt'}\" border='0'$attrs>";
    }
    if ($type eq "input") {
        return "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" ".
            "width=\"$i->{'width'}\" height=\"$i->{'height'}\" ".
            "alt=\"$i->{'alt'}\" border='0'$attrs>";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::load_user_props
# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: dbarg, u, propname*
# des-propname: the name of a property from the userproplist table.
# </LJFUNC>
sub load_user_props
{
    my $dbarg = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    ## user reference
    my ($uref, @props) = @_;
    my $uid = $uref->{'userid'}+0;
    unless ($uid) {
        $uid = LJ::get_userid($dbarg, $uref->{'user'});
    }

    my $propname_where;
    if (@props) {
        $propname_where = "AND upl.name IN (" . join(",", map { $dbh->quote($_) } @props) . ")";
    }

    my ($sql, $sth);

    # FIXME: right now we read userprops from both tables (indexed and
    # lite).  we always have to do this for cases when we're loading
    # all props, but when loading a subset, we might be able to
    # eliminate one query or the other if we cache somewhere the
    # userproplist and which props are in which table.  For now,
    # though, this works:

    foreach my $table (qw(userprop userproplite))
    {
        $sql = "SELECT upl.name, up.value FROM $table up, userproplist upl ".
            "WHERE up.userid=$uid AND up.upropid=upl.upropid $propname_where";
        $sth = $dbr->prepare($sql);
        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            $uref->{$_->{'name'}} = $_->{'value'};
        }
        $sth->finish;
    }

    # Add defaults to user object.

    # If this was called with no @props, then the function tried
    # to load all metadata.  but we don't know what's missing, so
    # try to apply all defaults.
    unless (@props) { @props = keys %LJ::USERPROP_DEF; }

    foreach my $prop (@props) {
        next if (defined $uref->{$prop});
        $uref->{$prop} = $LJ::USERPROP_DEF{$prop};
    }
}

# <LJFUNC>
# name: LJ::bad_input
# des: Returns common BML for reporting form validation errors in
#      a bulletted list.
# returns: BML showing errors.
# args: error*
# des-error: A list of errors
# </LJFUNC>
sub bad_input
{
    my @errors = @_;
    my $ret = "";
    $ret .= "(=BADCONTENT=)\n<ul>\n";
    foreach (@errors) {
        $ret .= "<li>$_</li>\n";
    }
    $ret .= "</ul>\n";
    return $ret;
}

# <LJFUNC>
# name: LJ::debug
# des: When $LJ::DEBUG is set, logs the given message to
#      $LJ::VAR/debug.log.  Or, if $LJ::DEBUG is 2, then
#      prints to STDOUT.
# returns: 1 if logging disabled, 0 on failure to open log, 1 otherwise
# args: message
# des-message: Message to log.
# </LJFUNC>
sub debug
{
    return 1 unless ($LJ::DEBUG);
    if ($LJ::DEBUG == 2) {
        print $_[0], "\n";
        return 1;
    }
    open (L, ">>$LJ::VAR/debug.log") or return 0;
    print L scalar(time), ": $_[0]\n";
    close L;
    return 1;
}

# <LJFUNC>
# name: LJ::auth_okay
# des: Validates a user's password.  The "clear" or "md5" argument
#      must be present, and either the "actual" argument (the correct
#      password) must be set, or the first argument must be a user
#      object ($u) with the 'password' key set.  Note that this is
#      the preferred way to validate a password (as opposed to doing
#      it by hand) since this function will use a pluggable authenticator
#      if one is defined, so LiveJournal installations can be based
#      off an LDAP server, for example.
# returns: boolean; 1 if authentication succeeded, 0 on failure
# args: user_u, clear, md5, actual?
# des-user_u: Either the user name or a user object.
# des-clear: Clear text password the client is sending. (need this or md5)
# des-md5: MD5 of the password the client is sending. (need this or clear).
#          If this value instead of clear, clear can be anything, as md5
#          validation will take precedence.
# des-actual: The actual password for the user.  Ignored if a pluggable
#             authenticator is being used.  Required unless the first
#             argument is a user object instead of a username scalar.
# </LJFUNC>
sub auth_okay
{
    my $user = shift;
    my $clear = shift;
    my $md5 = shift;
    my $actual = shift;

    # first argument can be a user object instead of a string, in
    # which case the actual password (last argument) is got from the
    # user object.
    if (ref $user eq "HASH") {
        $actual = $user->{'password'};
        $user = $user->{'user'};
    }

    ## custom authorization:
    if (ref $LJ::AUTH_CHECK eq "CODE") {
        my $type = $md5 ? "md5" : "clear";
        my $try = $md5 || $clear;
        return $LJ::AUTH_CHECK->($user, $try, $type);
    }

    ## LJ default authorization:
    return 1 if ($md5 && lc($md5) eq LJ::hash_password($actual));
    return 1 if ($clear eq $actual);
    return 0;
}

# <LJFUNC>
# name: LJ::create_account
# des: Creates a new basic account.  <b>Note:</b> This function is
#      not really too useful but should be extended to be useful so
#      htdocs/create.bml can use it, rather than doing the work itself.
# returns: integer of userid created, or 0 on failure.
# args: dbarg, opts
# des-opts: hashref containing keys 'user', 'name', and 'password'
# </LJFUNC>
sub create_account
{
    my $dbarg = shift;
    my $o = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $user = LJ::canonical_username($o->{'user'});
    unless ($user)  {
        return 0;
    }

    my $quser = $dbr->quote($user);
    my $qpassword = $dbr->quote($o->{'password'});
    my $qname = $dbr->quote($o->{'name'});

    my $cluster = $LJ::DEFAULT_CLUSTER + 0;

    my $sth = $dbh->prepare("INSERT INTO user (user, name, password, clusterid, dversion) ".
                            "VALUES ($quser, $qname, $qpassword, $cluster, 2)");
    $sth->execute;
    if ($dbh->err) { return 0; }

    my $userid = $sth->{'mysql_insertid'};
    $dbh->do("INSERT INTO useridmap (userid, user) VALUES ($userid, $quser)");
    $dbh->do("INSERT INTO userusage (userid, timecreate) VALUES ($userid, NOW())");

    LJ::run_hooks("post_create", {
        'dbs' => $dbs,
        'userid' => $userid,
        'user' => $user,
        'code' => undef,
    });
    return $userid;
}

# <LJFUNC>
# name: LJ::is_friend
# des: Checks to see if a user is a friend of another user.
# returns: boolean; 1 if user B is a friend of user A or if A == B
# args: dbarg, usera, userb
# des-usera: Source user hashref or userid.
# des-userb: Destination user hashref or userid. (can be undef)
# </LJFUNC>
sub is_friend
{
    my $dbarg = shift;
    my $ua = shift;
    my $ub = shift;

    my $uaid = (ref $ua ? $ua->{'userid'} : $ua)+0;
    my $ubid = (ref $ub ? $ub->{'userid'} : $ub)+0;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return 0 unless $uaid;
    return 0 unless $ubid;
    return 1 if ($uaid == $ubid);

    my $sth = $dbr->prepare("SELECT COUNT(*) FROM friends WHERE ".
                            "userid=$uaid AND friendid=$ubid");
    $sth->execute;
    my ($is_friend) = $sth->fetchrow_array;
    $sth->finish;
    return $is_friend;
}

# <LJFUNC>
# name: LJ::is_banned
# des: Checks to see if a user is banned from a journal.
# returns: boolean; 1 iff user B is banned from journal A
# args: dbarg, user, journal
# des-user: User hashref or userid.
# des-journal: Journal hashref or userid.
# </LJFUNC>
sub is_banned
{
    my $dbarg = shift;
    my $u = shift;
    my $j = shift;

    my $uid = (ref $u ? $u->{'userid'} : $u)+0;
    my $jid = (ref $j ? $j->{'userid'} : $j)+0;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return 1 unless $uid;
    return 1 unless $jid;

    # for speed: common case is non-community posting and replies
    # in own journal.  avoid db hit.
    return 0 if ($uid == $jid);

    my $sth = $dbr->prepare("SELECT COUNT(*) FROM ban WHERE ".
                            "userid=$jid AND banneduserid=$uid");
    $sth->execute;
    my $is_banned = $sth->fetchrow_array;
    $sth->finish;
    return $is_banned;
}

# <LJFUNC>
# name: LJ::can_view
# des: Checks to see if the remote user can view a given journal entry.
#      <b>Note:</b> This is meant for use on single entries at a time,
#      not for calling many times on every entry in a journal.
# returns: boolean; 1 if remote user can see item
# args: dbarg, remote, item
# des-item: Hashref from the 'log' table.
# </LJFUNC>
sub can_view
{
    my $dbarg = shift;
    my $remote = shift;
    my $item = shift;

    # public is okay
    return 1 if ($item->{'security'} eq "public");

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid = int($item->{'ownerid'});
    my $remoteid = int($remote->{'userid'});

    # owners can always see their own.
    return 1 if ($userid == $remoteid);

    # other people can't read private
    return 0 if ($item->{'security'} eq "private");

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless ($item->{'security'} eq "usemask");

    # usemask
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT groupmask FROM friends WHERE ".
                            "userid=$userid AND friendid=$remoteid");
    $sth->execute;
    my ($gmask) = $sth->fetchrow_array;
    my $allowed = (int($gmask) & int($item->{'allowmask'}));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# <LJFUNC>
# name: LJ::get_talktext
# des: Efficiently retrieves a large number of comments, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_logtext]].
# args: dbs, opts?, talkid*
# returns: hashref with keys being talkids, values being [ $subject, $body ]
# des-opts: Optional hashref of flags.  Currently supported key: 'onlysubjects',
#           which won't return body text:  $body will be undef.
# des-talkid: List of talkids to retrieve the subject & text for.
# </LJFUNC>
sub get_talktext
{
    my $dbs = shift;
    my $opts = ref $_[0] eq "HASH" ? shift : {};

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is
    # available, hit that first.
    my @sources = ([$dbs->{'dbh'}, "talktext"]);
    if ($dbs->{'has_slave'}) {
        if ($LJ::USE_RECENT_TABLES) {
            my $dbt = LJ::get_dbh("recenttext");
            unshift @sources, [ $dbt || $dbs->{'dbr'}, "recent_talktext" ];
        } else {
            unshift @sources, [ $dbs->{'dbr'}, "talktext" ];
        }
    }

    my $bodycol = $opts->{'onlysubjects'} ? "" : ", body";

    while (@sources && %need)
    {
        my $s = shift @sources;
        my ($db, $table) = ($s->[0], $s->[1]);
        my $talkid_in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT talkid, subject $bodycol FROM $table ".
                               "WHERE talkid IN ($talkid_in)");
        $sth->execute;
        while (my ($id, $subject, $body) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $body ];
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_logtext
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext]].
# args: dbs, opts?, itemid*
# des-opts: Optional hashref of special options.  Currently only 'prefersubjects'
#           key is supported, which returns subjects instead of events when
#           there's a subject, and the subject always being undef.
# des-itemid: List of itemids to retrieve the subject & text for.
# returns: hashref with keys being itemids, values being [ $subject, $body ]
# </LJFUNC>
sub get_logtext
{
    my $dbs = shift;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is
    # available, hit that first.
    my @sources = ([$dbs->{'dbh'}, "logtext"]);
    if ($dbs->{'has_slave'} && ! $opts->{'usemaster'}) {
        if ($LJ::USE_RECENT_TABLES) {
            my $dbt = LJ::get_dbh("recenttext");
            unshift @sources, [ $dbt || $dbs->{'dbr'}, "recent_logtext" ];
        } else {
            unshift @sources, [ $dbs->{'dbr'}, "logtext" ];
        }
    }

    my $snag_what = "subject, event";
    $snag_what = "NULL, IF(LENGTH(subject), subject, event)"
        if $opts->{'prefersubjects'};

    while (@sources && %need)
    {
        my $s = shift @sources;
        my ($db, $table) = ($s->[0], $s->[1]);
        my $itemid_in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT itemid, $snag_what FROM $table ".
                               "WHERE itemid IN ($itemid_in)");
        $sth->execute;
        while (my ($id, $subject, $event) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $event ];
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_logtext2
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext2]].
# args: u, opts?, jitemid*
# returns: hashref with keys being jitemids, values being [ $subject, $body ]
# des-opts: Optional hashref of special options.  Currently only 'prefersubjects'
#           key is supported, which returns subjects instead of events when
#           there's a subject, and the subject always being undef.
# des-jitemid: List of jitemids to retrieve the subject & text for.
# </LJFUNC>
sub get_logtext2
{
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'}+0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    my $dbh = LJ::get_dbh("cluster$clusterid");
    my $dbr = $opts->{'usemaster'} ? undef : LJ::get_dbh("cluster${clusterid}slave");

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is
    # available, hit that first.
    my @sources = ([$dbh, "logtext2"]);
    if ($dbr) {
        unshift @sources, [ $dbr, "logtext2" ];
    }

    my $snag_what = "subject, event";
    $snag_what = "NULL, IF(LENGTH(subject), subject, event)"
        if $opts->{'prefersubjects'};

    while (@sources && %need)
    {
        my $s = shift @sources;
        my ($db, $table) = ($s->[0], $s->[1]);
        next unless $db;
        my $jitemid_in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT jitemid, $snag_what FROM $table ".
                               "WHERE journalid=$journalid AND jitemid IN ($jitemid_in)");
        $sth->execute;
        while (my ($id, $subject, $event) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $event ];
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_talktext2
# des: Retrieves comment text. Tries slave servers first, then master.
# info: Efficiently retreives batches of comment text. Will try alternate
#       servers first. See also [func[LJ::get_logtext2]].
# returns: Hashref with the talkids as keys, values being [ $subject, $event ].
# args: u, opts?, jtalkids
# des-opts: A hashref of options. 'usermaster' will force checking of the
#           master only.
# des-jtalkids: A list of talkids to get text for.
# </LJFUNC>
sub get_talktext2
{
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'}+0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    my $dbh = LJ::get_dbh("cluster$clusterid");
    my $dbr = $opts->{'usemaster'} ? undef : LJ::get_dbh("cluster${clusterid}slave");

    # keep track of itemids we still need to load.
    my %need;
    foreach (@_) { $need{$_+0} = 1; }

    # always consider hitting the master database, but if a slave is
    # available, hit that first.
    my @sources = ([$dbh, "talktext2"]);
    if ($dbr) {
        unshift @sources, [ $dbr, "talktext2" ];
    }

    while (@sources && %need)
    {
        my $s = shift @sources;
        my ($db, $table) = ($s->[0], $s->[1]);
        my $in = join(", ", keys %need);

        my $sth = $db->prepare("SELECT jtalkid, subject, body FROM $table ".
                               "WHERE journalid=$journalid AND jtalkid IN ($in)");
        $sth->execute;
        while (my ($id, $subject, $event) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $event ];
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_logtext2multi
# des: Gets log text from clusters.
# info: Fetches log text from clusters. Trying slaves first if available.
# returns: hashref with keys being "jid jitemid", values being [ $subject, $body ]
# args: idsbyc
# des-idsbyc: A hashref where the key is the clusterid, and the data
#             is an arrayref of [ ownerid, itemid ] array references.
# </LJFUNC>
sub get_logtext2multi
{
    my ($dbs, $idsbyc) = @_;
    my $sth;

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load per cluster
    my %need;
    my @needold;
    foreach my $c (keys %$idsbyc) {
        foreach (@{$idsbyc->{$c}}) {
            if ($c) {
                $need{$c}->{"$_->[0] $_->[1]"} = 1;
            } else {
                push @needold, $_+0;
            }
        }
    }

    # don't handle non-cluster stuff ourselves
    if (@needold)
    {
        my $olt = LJ::get_logtext($dbs, @needold);
        foreach (keys %$olt) {
            $lt->{"0 $_"} = $olt->{$_};
        }
    }

    # pass 1: slave (trying recent), pass 2: master
    foreach my $pass (1, 2)
    {
        foreach my $c (keys %need)
        {
            next unless keys %{$need{$c}};
            my $table = "logtext2";
            my $db = $pass == 1 ? LJ::get_dbh("cluster${c}slave") :
                LJ::get_dbh("cluster${c}");
            next unless $db;

            my $fattyin;
            foreach (keys %{$need{$c}}) {
                $fattyin .= " OR " if $fattyin;
                my ($a, $b) = split(/ /, $_);
                $fattyin .= "(journalid=$a AND jitemid=$b)";
            }

            $sth = $db->prepare("SELECT journalid, jitemid, subject, event ".
                                "FROM $table WHERE $fattyin");
            $sth->execute;
            while (my ($jid, $jitemid, $subject, $event) = $sth->fetchrow_array) {
                delete $need{$c}->{"$jid $jitemid"};
                $lt->{"$jid $jitemid"} = [ $subject, $event ];
            }
        }
    }

    return $lt;
}

# <LJFUNC>
# name: LJ::make_text_link
# des: The most pathetic function of them all.  AOL's shitty mail
#      reader interprets all incoming mail as HTML formatted, even if
#      the content type says otherwise.  And AOL users are all too often
#      confused by a a URL that isn't clickable, so to make it easier on
#      them (*sigh*) this function takes a URL and an email address, and
#      if the address is @aol.com, then this function wraps the URL in
#      an anchor tag to its own address.  I'm sorry.
# returns: the same URL, or the URL wrapped in an anchor tag for AOLers
# args: url, email
# des-url: URL to return or wrap.
# des-email: Email address this is going to.  If it's @aol.com, the URL
#            will be wrapped.
# </LJFUNC>
sub make_text_link
{
    my ($url, $email) = @_;
    if ($email =~ /\@aol\.com$/i) {
        return "<a href=\"$url\">$url</a>";
    }
    return $url;
}

# <LJFUNC>
# name: LJ::get_remote
# des: authenticates the user at the remote end based on their cookies
#      and returns a hashref representing them
# returns: hashref containing 'user' and 'userid' if valid user, else
#          undef.
# args: dbarg, criterr?, cgi?
# des-criterr: scalar ref to set critical error flag.  if set, caller
#              should stop processing whatever it's doing and complain
#              about an invalid login with a link to the logout page.
# des-cgi: Optional CGI.pm reference if using in a script which
#          already uses CGI.pm.
# </LJFUNC>
sub get_remote
{
    my $dbarg = shift;
    my $criterr = shift;
    my $cgi = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $$criterr = 0;

    my $cookie = sub {
        return $cgi ? $cgi->cookie($_[0]) : $BMLClient::COOKIE{$_[0]};
    };

    my ($user, $userid, $caps);

    my $validate = sub {
        my $a = shift;
        # let hooks reject credentials, or set criterr true:
        my $hookparam = {
            'user' => $a->{'user'},
            'userid' => $a->{'userid'},
            'dbs' => $dbs,
            'caps' => $a->{'caps'},
            'criterr' => $criterr,
            'cookiesource' => $cookie,
        };
        my @r = LJ::run_hooks("validate_get_remote", $hookparam);
        return undef if grep { ! $_->[0] } @r;
        return 1;
    };

    ### are they logged in?
    unless ($user = $cookie->('ljuser')) {
        $validate->();
        return undef;
    }

    ### does their login password match their login?
    my $hpass = $cookie->('ljhpass');
    unless ($hpass =~ /^$user:(.+)/) {
        $validate->();
        return undef;
    }
    my $remhpass = $1;
    my $correctpass;     # find this out later.

    unless (ref $LJ::AUTH_CHECK eq "CODE") {
        my $quser = $dbr->quote($user);
        ($userid, $correctpass, $caps) =
            $dbr->selectrow_array("SELECT userid, password, caps ".
                                  "FROM user WHERE user=$quser");

        # each handler must return true, else credentials are ignored:
        return undef unless $validate->({
            'userid' => $userid,
            'user' => $user,
            'caps' => $caps,
        });

    } else {
        $userid = LJ::get_userid($dbh, $user);
    }

    unless ($userid && LJ::auth_okay($user, undef, $remhpass, $correctpass)) {
        $validate->();
        return undef;
    }

    return { 'user' => $user,
             'userid' => $userid, };
}

# <LJFUNC>
# name: LJ::load_remote
# des: Given a partial remote user hashref (from [func[LJ::get_remote]]),
#      loads in the rest, unless it's already loaded.
# args: dbarg, remote
# des-remote: Hashref containing 'user' and 'userid' keys at least.  This
#             hashref will be populated with the rest of the 'user' table
#             data.  If undef, does nothing.
# </LJFUNC>
sub load_remote
{
    my $dbarg = shift;
    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $remote = shift;
    return unless $remote;

    # if all three of these are loaded, this hashref is probably full.
    # (don't want to just test for 2 keys, since keys like '_priv' and
    # _privloaded might be present)
    return if (defined $remote->{'email'} &&
               defined $remote->{'caps'} &&
               defined $remote->{'status'});

    # try to load this remote user's record
    my $ru = LJ::load_userid($dbs, $remote->{'userid'});
    return unless $ru;

    # merge user record (so we preserve underscore key data structures)
    foreach my $k (keys %$ru) {
        $remote->{$k} = $ru->{$k};
    }
}

# <LJFUNC>
# name: LJ::get_remote_noauth
# des: returns who the remote user says they are, but doesn't check
#      their login token.  disadvantage: insecure, only use when
#      you're not doing anything critical.  advantage:  faster.
# returns: hashref containing only key 'user', not 'userid' like
#          [func[LJ::get_remote]].
# </LJFUNC>
sub get_remote_noauth
{
    ### are they logged in?
    my $remuser = $BMLClient::COOKIE{"ljuser"};
    return undef unless ($remuser =~ /^\w{1,15}$/);

    ### does their login password match their login?
    return undef unless ($BMLClient::COOKIE{"ljhpass"} =~ /^$remuser:(.+)/);
    return { 'user' => $remuser, };
}

# <LJFUNC>
# name: LJ::did_post
# des: When web pages using cookie authentication, you can't just trust that
#      the remote user wants to do the action they're requesting.  It's way too
#      easy for people to force other people into making GET requests to
#      a server.  What if a user requested http://server/delete_all_journal.bml
#      and that URL checked the remote user and immediately deleted the whole
#      journal.  Now anybody has to do is embed that address in an image
#      tag and a lot of people's journals will be deleted without them knowing.
#      Cookies should only show pages which make no action.  When an action is
#      being made, check that it's a POST request.
# returns: true if REQUEST_METHOD == "POST"
# </LJFUNC>
sub did_post
{
    return ($ENV{'REQUEST_METHOD'} eq "POST");
}

# <LJFUNC>
# name: LJ::clear_caches
# des: This function is called from a HUP signal handler and is intentionally
#      very very simple (1 line) so we don't core dump on a system without
#      reentrant libraries.  It just sets a flag to clear the caches at the
#      beginning of the next request (see [func[LJ::handle_caches]]).
#      There should be no need to ever call this function directly.
# </LJFUNC>
sub clear_caches
{
    $LJ::CLEAR_CACHES = 1;
}

# <LJFUNC>
# name: LJ::handle_caches
# des: clears caches if the CLEAR_CACHES flag is set from an earlier
#      HUP signal that called [func[LJ::clear_caches]], otherwise
#      does nothing.
# returns: true (always) so you can use it in a conjunction of
#          statements in a while loop around the application like:
#          while (LJ::handle_caches() && FCGI::accept())
# </LJFUNC>
sub handle_caches
{
    return 1 unless ($LJ::CLEAR_CACHES);
    $LJ::CLEAR_CACHES = 0;

    do "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

    foreach (keys %LJ::DBCACHE) {
        my $v = $LJ::DBCACHE{$_};
        next unless ref $v;
        $v->disconnect;
    }
    %LJ::DBCACHE = ();

    %LJ::CACHE_PROP = ();
    %LJ::CACHE_STYLE = ();
    $LJ::CACHED_MOODS = 0;
    $LJ::CACHED_MOOD_MAX = 0;
    %LJ::CACHE_MOODS = ();
    %LJ::CACHE_MOOD_THEME = ();
    %LJ::CACHE_USERID = ();
    %LJ::CACHE_USERNAME = ();
    %LJ::CACHE_USERPIC_SIZE = ();
    %LJ::CACHE_CODES = ();
    %LJ::CACHE_USERPROP = ();  # {$prop}->{ 'upropid' => ... , 'indexed' => 0|1 };
    %LJ::CACHE_ENCODINGS = ();
    return 1;
}

# <LJFUNC>
# name: LJ::start_request
# des: Before a new web request is obtained, this should be called to
#      determine if process should die or keep working, clean caches,
#      reload config files, etc.
# returns: 1 if a new request is to be processed, 0 if process should die.
# </LJFUNC>
sub start_request
{
    handle_caches();
    # TODO: check process growth size
    # TODO: auto-restat and reload ljconfig.pl if changed.

    # clear %LJ::DBREQCACHE (like DBCACHE, but verified already for
    # this request to be ->ping'able).
    %LJ::DBREQCACHE = ();

    # need to suck db weights down on every request (we check
    # the serial number of last db weight change on every request
    # to validate master db connection, instead of selecting
    # the connection ID... just as fast, but with a point!)
    if ($LJ::DBWEIGHTS_FROM_DB) {  # defined in ljconfig.pl
        $LJ::NEED_DBWEIGHTS = 1;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpic at once.
# args: dbarg, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: arrayref of picids to load
# </LJFUNC>
sub load_userpics
{
    my ($dbarg, $upics, $idlist) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my @load_list;
    foreach my $id (@{$idlist})
    {
        if ($LJ::CACHE_USERPIC_SIZE{$id}) {
            $upics->{$id}->{'width'} = $LJ::CACHE_USERPIC_SIZE{$id}->{'width'};
            $upics->{$id}->{'height'} = $LJ::CACHE_USERPIC_SIZE{$id}->{'height'};
        } elsif ($id+0) {
            push @load_list, ($id+0);
        }
    }
    return unless (@load_list);
    my $picid_in = join(",", @load_list);
    my $sth = $dbr->prepare("SELECT picid, width, height FROM userpic WHERE picid IN ($picid_in)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        my $id = $_->{'picid'};
        undef $_->{'picid'};
        $upics->{$id} = $_;
        $LJ::CACHE_USERPIC_SIZE{$id}->{'width'} = $_->{'width'};
        $LJ::CACHE_USERPIC_SIZE{$id}->{'height'} = $_->{'height'};
    }
}

# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.
# args: opt
# des-opt: Hashref of arguments.  <b>Required:</b> to, from, subject, body.
#          <b>Optional:</b> toname, fromname, cc, bcc
# </LJFUNC>
sub send_mail
{
    my $opt = shift;
    open (MAIL, "|$LJ::SENDMAIL");
    my $toname;
    if ($opt->{'toname'}) {
        $opt->{'toname'} =~ s/[\n\t\(\)]//g;
        $toname = " ($opt->{'toname'})";
    }
    print MAIL "To: $opt->{'to'}$toname\n";
    print MAIL "Cc: $opt->{'bcc'}\n" if ($opt->{'cc'});
    print MAIL "Bcc: $opt->{'bcc'}\n" if ($opt->{'bcc'});
    print MAIL "From: $opt->{'from'}";
    if ($opt->{'fromname'}) {
        print MAIL " ($opt->{'fromname'})";
    }
    print MAIL "\nSubject: $opt->{'subject'}\n\n";
    print MAIL $opt->{'body'};
    close MAIL;
}

# <LJFUNC>
# name: LJ::strip_bad_code
# class: security
# des: Removes malicious/annoying HTML.
# info: This is just a wrapper function around [func[LJ::CleanHTML::clean]].
# args: textref
# des-textref: Scalar reference to text to be cleaned.
# returns: Nothing.
# </LJFUNC>
sub strip_bad_code
{
    my $data = shift;
    LJ::CleanHTML::clean($data, {
        'eat' => [qw[layer iframe script]],
        'mode' => 'allow',
        'keepcomments' => 1, # Allows CSS to work
    });
}

# <LJFUNC>
# name: LJ::load_user_theme
# des: Populates a variable hash with color theme data.
# returns: Nothing. Modifies a hash reference.
# args: user, u, vars
# des-user: The username to search for data with.
# des-vars: A hashref to fill with color data. Adds keys "color-$coltype"
#           with values $color.
# </LJFUNC>
sub load_user_theme
{
    # hashref, hashref
    my ($dbarg, $user, $u, $vars) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $sth;
    my $quser = $dbh->quote($user);

    if ($u->{'themeid'} == 0) {
        $sth = $dbr->prepare("SELECT coltype, color FROM themecustom WHERE user=$quser");
    } else {
        my $qtid = $dbh->quote($u->{'themeid'});
        $sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=$qtid");
    }
    $sth->execute;
    $vars->{"color-$_->{'coltype'}"} = $_->{'color'} while ($_ = $sth->fetchrow_hashref);
}

# <LJFUNC>
# class: s1
# name: LJ::parse_vars
# des: Parses S1 style data into hashref.
# returns: Nothing.  Modifies a hashref.
# args: dataref, hashref
# des-dataref: Reference to scalar with data to parse. Format is
#              a BML-style full block, as used in the S1 style system.
# des-hashref: Hashref to populate with data.
# </LJFUNC>
sub parse_vars
{
    my ($dataref, $hashref) = @_;
    my @data = split(/\n/, $$dataref);
    my $curitem = "";

    foreach (@data)
    {
        $_ .= "\n";
        s/\r//g;
        if ($curitem eq "" && /^([A-Z0-9\_]+)=>([^\n\r]*)/)
        {
            $hashref->{$1} = $2;
        }
        elsif ($curitem eq "" && /^([A-Z0-9\_]+)<=\s*$/)
        {
            $curitem = $1;
            $hashref->{$curitem} = "";
        }
        elsif ($curitem && /^<=$curitem\s*$/)
        {
            chop $hashref->{$curitem};  # remove the false newline
            $curitem = "";
        }
        else
        {
            $hashref->{$curitem} .= $_ if ($curitem =~ /\S/);
        }
    }
}

# <LJFUNC>
# name: LJ::server_down_html
# des: Returns an HTML server down message.
# returns: A string with a server down message in HTML.
# </LJFUNC>
sub server_down_html
{
    return "<b>$LJ::SERVER_DOWN_SUBJECT</b><br />$LJ::SERVER_DOWN_MESSAGE";
}

# <LJFUNC>
# class: s1
# name: LJ::load_style_fast
# des: Loads a style, and does minimal caching (data sticks for 60 seconds).
# returns: Nothing. Modifies a data reference.
# args: styleid, dataref, typeref, nocache?
# des-styleid: Numeric, primary key.
# des-dataref: Dataref to store data in.
# des-typeref: Optional dataref to store the style tyep in (undef for none).
# des-nocache: Flag to say don't cache.
# </LJFUNC>
sub load_style_fast
{
    my ($dbarg, $styleid, $dataref, $typeref, $nocache) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $styleid += 0;
    my $now = time();

    if ((defined $LJ::CACHE_STYLE{$styleid}) &&
        ($LJ::CACHE_STYLE{$styleid}->{'lastpull'} > ($now-300)) &&
        (! $nocache)
        )
    {
        $$dataref = $LJ::CACHE_STYLE{$styleid}->{'data'};
        if (ref $typeref eq "SCALAR") { $$typeref = $LJ::CACHE_STYLE{$styleid}->{'type'}; }
    }
    else
    {
        my @h = ($dbh);
        if ($dbs->{'has_slave'}) {
            unshift @h, $dbr;
        }
        my ($data, $type, $cache);
        my $sth;
        foreach my $db (@h)
        {
            $sth = $dbr->prepare("SELECT formatdata, type, opt_cache FROM style WHERE styleid=$styleid");
            $sth->execute;
            ($data, $type, $cache) = $sth->fetchrow_array;
            $sth->finish;
            last if ($data);
        }
        if ($cache eq "Y") {
            $LJ::CACHE_STYLE{$styleid} = { 'lastpull' => $now,
                                       'data' => $data,
                                       'type' => $type,
                                   };
        }

        $$dataref = $data;
        if (ref $typeref eq "SCALAR") { $$typeref = $type; }
    }
}

# <LJFUNC>
# name: LJ::make_journal
# class:
# des:
# info:
# args: dbarg, user, view, remote, opts
# des-:
# returns:
# </LJFUNC>
sub make_journal
{
    my ($dbarg, $user, $view, $remote, $opts) = @_;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    if ($LJ::SERVER_DOWN) {
        if ($opts->{'vhost'} eq "customview") {
            return "<!-- LJ down for maintenance -->";
        }
        return LJ::server_down_html();
    }

    my ($styleid);
    if ($opts->{'styleid'}) {
        $styleid = $opts->{'styleid'}+0;
    } else {
        $view ||= "lastn";    # default view when none specified explicitly in URLs
        if ($LJ::viewinfo{$view})  {
            $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
            $view = $view;
        } else {
            $opts->{'badargs'} = 1;
        }
    }
    return unless ($styleid);

    my $quser = $dbh->quote($user);
    my $u;
    if ($opts->{'u'}) {
        $u = $opts->{'u'};
    } else {
        $u = LJ::load_user($dbs, $user);
    }

    unless ($u)
    {
        $opts->{'baduser'} = 1;
        return "<H1>Error</H1>No such user <B>$user</B>";
    }

    if ($styleid == -1) {
        if ($u->{"${view}_style"}) {
            # NOTE: old schema.  only here to make transition easier.  remove later.
            $styleid = $u->{"${view}_style"};
        } else {
            my $prop = "s1_${view}_style";
            unless (defined $u->{$prop}) {
              LJ::load_user_props($dbs, $u, $prop);
            }
            $styleid = $u->{$prop};
        }
    }

    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && ! LJ::get_cap($u, "userdomain")) {
        return "<b>Notice</b><br />Addresses like <tt>http://<i>username</i>.$LJ::USER_DOMAIN</tt> aren't enabled for this user's account type.  Instead, visit:<ul><font face=\"Verdana,Arial\"><b><a href=\"$LJ::SITEROOT/users/$user/\">$LJ::SITEROOT/users/$user/</a></b></font></ul>";
    }
    if ($opts->{'vhost'} eq "customview" && ! LJ::get_cap($u, "userdomain")) {
        return "<b>Notice</b><br />Only users with <A HREF=\"$LJ::SITEROOT/paidaccounts/\">paid accounts</A> can create and embed styles.";
    }
    if ($opts->{'vhost'} eq "community" && $u->{'journaltype'} ne "C") {
        return "<b>Notice</b><br />This account isn't a community journal.";
    }

    return "<h1>Error</h1>Journal has been deleted.  If you are <B>$user</B>, you have a period of 30 days to decide to undelete your journal." if ($u->{'statusvis'} eq "D");
    return "<h1>Error</h1>This journal has been suspended." if ($u->{'statusvis'} eq "S");
    return "<h1>Error</h1>This journal has been deleted and purged.  This username will be available shortly." if ($u->{'statusvis'} eq "X");

    my %vars = ();
    # load the base style
    my $basevars = "";
    LJ::load_style_fast($dbs, $styleid, \$basevars, \$view)
        unless ($LJ::viewinfo{$view}->{'nostyle'});

    # load the overrides
    my $overrides = "";
    if ($opts->{'nooverride'}==0 && $u->{'useoverrides'} eq "Y")
    {
        my $sth = $dbr->prepare("SELECT override FROM overrides WHERE user=$quser");
        $sth->execute;
        ($overrides) = $sth->fetchrow_array;
        $sth->finish;
    }

    # populate the variable hash
    LJ::parse_vars(\$basevars, \%vars);
    LJ::parse_vars(\$overrides, \%vars);
    LJ::load_user_theme($dbs, $user, $u, \%vars);

    # kinda free some memory
    $basevars = "";
    $overrides = "";

    # instruct some function to make this specific view type
    return unless (defined $LJ::viewinfo{$view}->{'creator'});
    my $ret = "";

    # call the view creator w/ the buffer to fill and the construction variables
    &{$LJ::viewinfo{$view}->{'creator'}}($dbs, \$ret, $u, \%vars, $remote, $opts);

    # remove bad stuff
    unless ($opts->{'trusted_html'}) {
        LJ::strip_bad_code(\$ret);
    }

    # return it...
    return $ret;
}

# <LJFUNC>
# name: LJ::html_datetime
# class: component
# des:
# info: Parse output later with [func[LJ::html_datetime_decode]].
# args:
# des-:
# returns:
# </LJFUNC>
sub html_datetime
{
    my $opts = shift;
    my $lang = $opts->{'lang'} || "EN";
    my ($yyyy, $mm, $dd, $hh, $nn, $ss);
    my $ret;
    my $name = $opts->{'name'};
    my $disabled = $opts->{'disabled'} ? "DISABLED" : "";
    if ($opts->{'default'} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d):(\d\d))/) {
        ($yyyy, $mm, $dd, $hh, $nn, $ss) = ($1 > 0 ? $1 : "",
                                            $2+0,
                                            $3 > 0 ? $3+0 : "",
                                            $4 > 0 ? $4 : "",
                                            $5 > 0 ? $5 : "",
                                            $6 > 0 ? $6 : "");
    }
    $ret .= LJ::html_select({ 'name' => "${name}_mm", 'selected' => $mm, 'disabled' => $opts->{'disabled'} },
                         map { $_, LJ::Lang::month_long($lang, $_) } (0..12));
    $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_dd VALUE=\"$dd\" $disabled>, <INPUT SIZE=4 MAXLENGTH=4 NAME=${name}_yyyy VALUE=\"$yyyy\" $disabled>";
    unless ($opts->{'notime'}) {
        $ret.= " <INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_hh VALUE=\"$hh\" $disabled>:<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_nn VALUE=\"$nn\" $disabled>";
        if ($opts->{'seconds'}) {
            $ret .= "<INPUT SIZE=2 MAXLENGTH=2 NAME=${name}_ss VALUE=\"$ss\" $disabled>";
        }
    }

    return $ret;
}

# <LJFUNC>
# name: LJ::html_datetime_decode
# class: component
# des:
# info: Generate the form controls with [func[LJ::html_datetime]].
# args:
# des-:
# returns:
# </LJFUNC>
sub html_datetime_decode
{
    my $opts = shift;
    my $hash = shift;
    my $name = $opts->{'name'};
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $hash->{"${name}_yyyy"},
                   $hash->{"${name}_mm"},
                   $hash->{"${name}_dd"},
                   $hash->{"${name}_hh"},
                   $hash->{"${name}_nn"},
                   $hash->{"${name}_ss"});
}

# <LJFUNC>
# name: LJ::html_select
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub html_select
{
    my $opts = shift;
    my @items = @_;
    my $disabled = $opts->{'disabled'} ? " disabled='1'" : "";
    my $ret;
    $ret .= "<select";
    if ($opts->{'name'}) { $ret .= " name='$opts->{'name'}'"; }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    $ret .= "$disabled>";
    while (my ($value, $text) = splice(@items, 0, 2)) {
        my $sel = "";
        if ($value eq $opts->{'selected'}) { $sel = " selected"; }
        $ret .= "<option value=\"$value\"$sel>$text</option>";
    }
    $ret .= "</select>";
    return $ret;
}

# <LJFUNC>
# name: LJ::html_check
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub html_check
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " DISABLED" : "";
    my $ret;
    if ($opts->{'type'} eq "radio") {
        $ret .= "<input type=\"radio\" ";
    } else {
        $ret .= "<input type=\"checkbox\" ";
    }
    if ($opts->{'selected'}) { $ret .= " checked='1'"; }
    if ($opts->{'raw'}) { $ret .= " $opts->{'raw'}"; }
    if ($opts->{'name'}) { $ret .= " name=\"$opts->{'name'}\""; }
    if (defined $opts->{'value'}) { $ret .= " value=\"$opts->{'value'}\""; }
    $ret .= "$disabled>";
    return $ret;
}

# <LJFUNC>
# name: LJ::html_text
# class: component
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub html_text
{
    my $opts = shift;

    my $disabled = $opts->{'disabled'} ? " DISABLED" : "";
    my $ret;
    $ret .= "<input type=\"text\"";
    if ($opts->{'size'}) { $ret .= " size=\"$opts->{'size'}\""; }
    if ($opts->{'maxlength'}) { $ret .= " maxlength=\"$opts->{'maxlength'}\""; }
    if ($opts->{'name'}) { $ret .= " name=\"" . LJ::ehtml($opts->{'name'}) . "\""; }
    if ($opts->{'value'}) { $ret .= " value=\"" . LJ::ehtml($opts->{'value'}) . "\""; }
    $ret .= "$disabled>";
    return $ret;
}

# <LJFUNC>
# name: LJ::canonical_username
# des:
# info:
# args: user
# returns: the canonical username given, or blank if the username is not well-formed
# </LJFUNC>
sub canonical_username
{
    my $user = shift;
    if ($user =~ /^\s*([\w\-]{1,15})\s*$/) {
        $user = lc($1);
        $user =~ s/-/_/g;
        return $user;
    }
    return "";  # not a good username.
}

# <LJFUNC>
# name: LJ::decode_url_string
# class: web
# des: Parse URL-style arg/value pairs into a hash.
# args: buffer, hashref
# des-buffer: Scalar or scalarref of buffer to parse.
# des-hashref: Hashref to populate.
# returns: boolean; true.
# </LJFUNC>
sub decode_url_string
{
    my $a = shift;
    my $buffer = ref $a ? $a : \$a;
    my $hashref = shift;  # output hash

    my $pair;
    my @pairs = split(/&/, $$buffer);
    my ($name, $value);
    foreach $pair (@pairs)
    {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $hashref->{$name} .= $hashref->{$name} ? "\0$value" : $value;
    }
    return 1;
}

# given two db roles, returns true only if the two roles are for sure
# served by different database servers.  this is useful for, say,
# the moveusercluster script:  you wouldn't want to select something
# from one db, copy it into another, and then delete it from the
# source if they were both the same machine.
# <LJFUNC>
# name: LJ::use_diff_db
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub use_diff_db
{
    my ($role1, $role2) = @_;

    return 0 if $role1 eq $role2;

    # this is implied:  (makes logic below more readable by forcing it)
    $LJ::DBINFO{'master'}->{'role'}->{'master'} = 1;

    foreach (keys %LJ::DBINFO) {
        next if /^_/;
        next unless ref $LJ::DBINFO{$_} eq "HASH";
        if ($LJ::DBINFO{$_}->{'role'}->{$role1} &&
            $LJ::DBINFO{$_}->{'role'}->{$role2}) {
            return 0;
        }
    }

    return 1;
}

# <LJFUNC>
# name: LJ::get_dbh
# class: db
# des: Given one or more roles, returns a database handle.
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_dbh
{
    my @roles = @_;
    my $role = shift @roles;
    return undef unless $role;

    my $now = time();

    # if non-master request and we haven't yet hit the master to get
    # the dbinfo, do that first.  (normal code path is something
    # calls LJ::start_request(), then gets master, then gets other)
    # but this path happens also.
    if ($role ne "master" && $LJ::DBWEIGHTS_FROM_DB &&
        ! $LJ::DBINFO{'_fromdb'})
    {
        # this might be enough to do it, if master isn't loaded:
        $LJ::NEED_DBWEIGHTS = 1;
        my $dbh = LJ::get_dbh("master");

        # or, if we already had a master cached, we have to
        # load it by hand:
        unless ($LJ::DBINFO{'_fromdb'}) {
            _reload_weights($dbh);
        }
    }

    # otherwise, see if we have a role -> full DSN mapping already
    my ($fdsn, $dbh);
    if ($role eq "master") {
        $fdsn = _make_dbh_fdsn($LJ::DBINFO{'master'});
    } else {
        if ($LJ::DBCACHE{$role}) {
            $fdsn = $LJ::DBCACHE{$role};
            if ($now > $LJ::DBCACHE_UNTIL{$role}) {
                # this role -> DSN mapping is too old.  invalidate,
                # and while we're at it, clean up any connections we have
                # that are too idle.
                undef $fdsn;

                foreach (keys %LJ::DB_USED_AT) {
                    next if $LJ::DB_USED_AT{$_} > $now - 60;
                    delete $LJ::DB_USED_AT{$_};
                    delete $LJ::DBCACHE{$_};
                }
            }
        }
    }

    if ($fdsn) {
        $dbh = _get_dbh_conn($fdsn, $role);
        return $dbh if $dbh;
        delete $LJ::DBCACHE{$role};  # guess it was bogus
    }
    return undef if $role eq "master";  # no hope now

    # time to randomly weightedly select one.
    my @applicable;
    my $total_weight;
    foreach (keys %LJ::DBINFO) {
        next if /^_/;
        next unless ref $LJ::DBINFO{$_} eq "HASH";
        my $weight = $LJ::DBINFO{$_}->{'role'}->{$role};
        next unless $weight;
        push @applicable, [ $LJ::DBINFO{$_}, $weight ];
        $total_weight += $weight;
    }

    while (@applicable)
    {
        my $rand = rand($total_weight);
        my ($i, $t) = (0, 0);
        for (; $i<@applicable; $i++) {
            $t += $applicable[$i]->[1];
            last if $t > $rand;
        }
        my $fdsn = _make_dbh_fdsn($applicable[$i]->[0]);
        $dbh = _get_dbh_conn($fdsn);
        if ($dbh) {
            $LJ::DBCACHE{$role} = $fdsn;
            $LJ::DBCACHE_UNTIL{$role} = $now + 20 + int(rand(10));
            return $dbh;
        }

        # otherwise, discard that one.
        $total_weight -= $applicable[$i]->[1];
        splice(@applicable, $i, 1);
    }

    # try others
    return get_dbh(@roles);
}

sub _make_dbh_fdsn
{
    my $db = shift;   # hashref with DSN info, from ljconfig.pl's %LJ::DBINFO
    return $db->{'_fdsn'} if $db->{'_fdsn'};  # already made?

    my $fdsn = "DBI:mysql";  # join("|",$dsn,$user,$pass) (because no refs as hash keys)
    $db->{'dbname'} ||= "livejournal";
    $fdsn .= ":$db->{'dbname'}:";
    if ($db->{'host'}) {
        $fdsn .= "host=$db->{'host'};";
    }
    if ($db->{'sock'}) {
        $fdsn .= "mysql_socket=$db->{'sock'};";
    }
    $fdsn .= "|$db->{'user'}|$db->{'pass'}";

    $db->{'_fdsn'} = $fdsn;
    return $fdsn;
}

sub _get_dbh_conn
{
    my $fdsn = shift;
    my $role = shift;  # optional.
    my $now = time();

    my $retdb = sub {
        my $db = shift;
        $LJ::DBREQCACHE{$fdsn} = $db;
        $LJ::DB_USED_AT{$fdsn} = $now;
        return $db;
    };

    # have we already created or verified a handle this request for this DSN?
    return $retdb->($LJ::DBREQCACHE{$fdsn})
        if $LJ::DBREQCACHE{$fdsn};

    # check to see if we recently tried to connect to that dead server
    return undef if $now < $LJ::DBDEADUNTIL{$fdsn};

    # if not, we'll try to find one we used sometime in this process lifetime
    my $dbh = $LJ::DBCACHE{$fdsn};

    # if it exists, verify it's still alive and return it:
    if ($dbh)
    {
        if ($role eq "master" && $LJ::NEED_DBWEIGHTS) {
            return $retdb->($dbh) if _reload_weights($dbh);
        } else {
            return $retdb->($dbh) if $dbh->selectrow_array("SELECT CONNECTION_ID()");
        }

        # bogus:
        undef $dbh;
        undef $LJ::DBCACHE{$fdsn};
    }

    # time to make one!
    my ($dsn, $user, $pass) = split(/\|/, $fdsn);
    $dbh = DBI->connect($dsn, $user, $pass, {
        PrintError => 0,
    });

    # mark server as dead if dead.  won't try to reconnect again for 5 seconds.
    if ($dbh) {
        $LJ::DB_USED_AT{$fdsn} = $now;
        if ($role eq "master" && $LJ::NEED_DBWEIGHTS) {
            _reload_weights($dbh);
        }
    } else {
        $LJ::DB_DEAD_UNTIL{$fdsn} = $now + 5;
    }

    return $LJ::DBREQCACHE{$fdsn} = $LJ::DBCACHE{$fdsn} = $dbh;
}

sub _reload_weights
{
    my $dbh = shift;

    my $serial =
        $dbh->selectrow_array("SELECT fdsn AS 'serial' FROM dbinfo WHERE dbid=0");

    return 0 if $dbh->err;
    $LJ::NEED_DBWEIGHTS = 0;
    return 1 if $serial == $LJ::CACHE_DBWEIGHT_SERIAL;

    my $sth = $dbh->prepare("SELECT i.masterid, i.name, i.fdsn, ".
                            "w.role, w.curr FROM dbinfo i, dbweights w ".
                            "WHERE i.dbid=w.dbid");
    $sth->execute;

    my %dbinfo;
    while (my $r = $sth->fetchrow_hashref) {
        my $name = $r->{'masterid'} ? $r->{'name'} : "master";
        $dbinfo{$name}->{'_fdsn'} = $r->{'fdsn'};
        $dbinfo{$name}->{'role'}->{$r->{'role'}} = $r->{'curr'};
        $dbinfo{$name}->{'_totalweight'} += $r->{'curr'};
    }

    # any host that has no total weight (temporarily disabled?), we want
    # to kill all its live connections.
    foreach my $h (keys %dbinfo) {
        my $i = $dbinfo{$h};
        next if $i->{'_totalweight'};

        # kill open OAconnections to it
        delete $LJ::DBCACHE{$i->{'_fdsn'}};

        # mark nothing as wanting to use it.
        foreach my $k (keys %LJ::DBCACHE) {
            next if ref $LJ::DBCACHE{$k};
            if ($LJ::DBCACHE{$k} eq $i->{'_fdsn'}) {
                delete $LJ::DBCACHE{$k};
            }
        }
    }

    # copy new config.  good to go!
    %LJ::DBINFO = %dbinfo;
    $LJ::DBINFO{'_fromdb'} = 1;
    1;
}

# <LJFUNC>
# name: LJ::get_dbs
# des: Returns a set of database handles to master and a slave,
#      if this site is using slave databases.  Only use this
#      once per connection and pass around the same $dbs, since
#      this function calls [func[LJ::get_dbh]] which uses cached
#      connections, but validates the connection is still live.
# returns: $dbs (see [func[LJ::make_dbs]])
# </LJFUNC>
sub get_dbs
{
    my $dbh = LJ::get_dbh("master");
    my $dbr = LJ::get_dbh("slave");

    # check to see if fdsns of connections we just got match.  if
    # slave ends up being master, we want to pretend we just have no
    # slave (avoids some queries being run twice on master).  this is
    # common when somebody sets up a master and 2 slaves, but has the
    # master doing 1 of the 3 configured slave roles
    $dbr = undef if $LJ::DBCACHE{"slave"} eq $LJ::DBCACHE{"master"};

    return make_dbs($dbh, $dbr);
}

# <LJFUNC>
# name: LJ::get_cluster_reader
# class: db
# des: Returns a cluster slave for a user, or cluster master if no slaves exist.
# args: uarg
# des-uarg: Either a userid scalar or a user object.
# returns: DB handle.  Or undef if all dbs are unavailable.
# </LJFUNC>
sub get_cluster_reader
{
    my $arg = shift;
    my $id = ref $arg eq "HASH" ? $arg->{'clusterid'} : $arg;
    return LJ::get_dbh("cluster${id}slave",
                       "cluster${id}");
}

# <LJFUNC>
# name: LJ::get_cluster_master
# class: db
# des: Returns a cluster master for a given user.
# args: uarg
# des-uarg: Either a userid scalar or a user object.
# returns: DB handle.  Or undef if master is unavailable.
# </LJFUNC>
sub get_cluster_master
{
    my $arg = shift;
    my $id = ref $arg eq "HASH" ? $arg->{'clusterid'} : $arg;
    return LJ::get_dbh("cluster${id}");
}

# <LJFUNC>
# name: LJ::get_cluster_set
# class: db
# des: Returns a dbset structure for a user's db clusters.
# args: uarg
# des-uarg: Either a userid scalar or a user object.
# returns: dbset.
# </LJFUNC>
sub get_cluster_set
{
    my $arg = shift;
    my $id = ref $arg eq "HASH" ? $arg->{'clusterid'} : $arg;
    my $dbs = {};
    $dbs->{'dbh'} = LJ::get_dbh("cluster${id}");
    $dbs->{'dbr'} = LJ::get_dbh("cluster${id}slave");

    # see note in LJ::get_dbs about why we do this:
    $dbs->{'dbr'} = undef
        if $LJ::DBCACHE{"cluster${id}"} eq $LJ::DBCACHE{"cluster${id}slave"};

    $dbs->{'has_slave'} = defined $dbs->{'dbr'};
    $dbs->{'reader'} = $dbs->{'has_slave'} ? $dbs->{'dbr'} : $dbs->{'dbh'};
    return $dbs;
}

# <LJFUNC>
# name: LJ::make_dbs
# class: db
# des: Makes a $dbs structure from a master db
#      handle and optionally a slave.  This function
#      is called from [func[LJ::get_dbs]].  You shouldn't need
#      to call it yourself.
# returns: $dbs: hashref with 'dbh' (master), 'dbr' (slave or undef),
#          'has_slave' (boolean) and 'reader' (dbr if defined, else dbh)
# </LJFUNC>
sub make_dbs
{
    my ($dbh, $dbr) = @_;
    my $dbs = {};
    $dbs->{'dbh'} = $dbh;
    $dbs->{'dbr'} = $dbr;
    $dbs->{'has_slave'} = defined $dbr ? 1 : 0;
    $dbs->{'reader'} = defined $dbr ? $dbr : $dbh;
    return $dbs;
}

# <LJFUNC>
# name: LJ::make_dbs_from_arg
# class: db
# des: Convert unknown arg to a dbset.
# info: Functions use this to let their callers use either db handles
#       or dbsets.  If argument is a single handle, turns it into a
#       dbset.  If already a dbset, just returns it unchanged.
# args: something
# des-something: Either a db handle or a dbset.
# returns: A dbset.
# </LJFUNC>
sub make_dbs_from_arg
{
    my $dbarg = shift;
    my $dbs;
    if (ref($dbarg) eq "HASH") {
        $dbs = $dbarg;
    } else {
        $dbs = LJ::make_dbs($dbarg, undef);
    }
    return $dbs;
}


# <LJFUNC>
# name: LJ::date_to_view_links
# class: component
# des: Returns HTML of date with links to user's journal.
# args: u, date
# des-date: date in yyyy-mm-dd form.
# returns: HTML with yyy, mm, and dd all links to respective views.
# </LJFUNC>
sub date_to_view_links
{
    my ($u, $date) = @_;

    return unless ($date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/);
    my ($y, $m, $d) = ($1, $2, $3);
    my ($nm, $nd) = ($m+0, $d+0);   # numeric, without leading zeros
    my $user = $u->{'user'};

    my $ret;
    $ret .= "<a href=\"$LJ::SITEROOT/users/$user/calendar/$y\">$y</a>-";
    $ret .= "<a href=\"$LJ::SITEROOT/view/?type=month&amp;user=$user&amp;y=$y&amp;m=$nm\">$m</a>-";
    $ret .= "<a href=\"$LJ::SITEROOT/users/$user/day/$y/$m/$d\">$d</a>";
    return $ret;
}

# <LJFUNC>
# name: LJ::item_link
# class: component
# des: Returns URL to view an individual journal item.
# info: The returned URL may have an ampersand in it.  In an HTML/XML attribute,
#       these must first be escaped by, say, [func[LJ::ehtml]].  This
#       function doesn't return it pre-escaped because the caller may
#       use it in, say, a plain-text email message.
# args: u, itemid, anum?
# des-itemid: Itemid of entry to link to.
# des-anum: If present, $u is assumed to be on a cluster and itemid is assumed
#           to not be a $ditemid already, and the $itemid will be turned into one
#           by multiplying by 256 and adding $anum.
# returns: scalar; unescaped URL string
# </LJFUNC>
sub item_link
{
    my ($u, $itemid, $anum) = @_;
    my $jarg = $u->{'clusterid'} ? "journal=$u->{'user'}&" : "";
    my $ditemid = defined $anum ? ($itemid*256 + $anum) : $itemid;
    return "$LJ::SITEROOT/talkread.bml?${jarg}itemid=$ditemid";
}

# <LJFUNC>
# name: LJ::make_graphviz_dot_file
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub make_graphviz_dot_file
{
    my $dbarg = shift;
    my $user = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $quser = $dbr->quote($user);
    my $sth;
    my $ret;

    $sth = $dbr->prepare("SELECT u.*, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(uu.timeupdate) AS 'secondsold' FROM user u, userusage uu WHERE u.userid=uu.userid AND u.user=$quser");
    $sth->execute;
    my $u = $sth->fetchrow_hashref;

    unless ($u) {
        return "";
    }

    $ret .= "digraph G {\n";
    $ret .= "  node [URL=\"$LJ::SITEROOT/userinfo.bml?user=\\N\"]\n";
    $ret .= "  node [fontsize=10, color=lightgray, style=filled]\n";
    $ret .= "  \"$user\" [color=yellow, style=filled]\n";

    my @friends = ();
    $sth = $dbr->prepare("SELECT friendid FROM friends WHERE userid=$u->{'userid'} AND userid<>friendid");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        push @friends, $_->{'friendid'};
    }

    my $friendsin = join(", ", map { $dbh->quote($_); } ($u->{'userid'}, @friends));
    my $sql = "SELECT uu.user, uf.user AS 'friend' FROM friends f, user uu, user uf WHERE f.userid=uu.userid AND f.friendid=uf.userid AND f.userid<>f.friendid AND uu.statusvis='V' AND uf.statusvis='V' AND (f.friendid=$u->{'userid'} OR (f.userid IN ($friendsin) AND f.friendid IN ($friendsin)))";
    $sth = $dbr->prepare($sql);
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        $ret .= "  \"$_->{'user'}\"->\"$_->{'friend'}\"\n";
    }

    $ret .= "}\n";

    return $ret;
}

# <LJFUNC>
# name: LJ::expand_embedded
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub expand_embedded
{
    my $dbs = shift;
    my $ditemid = shift;
    my $remote = shift;
    my $eventref = shift;

    LJ::Poll::show_polls($dbs, $ditemid, $remote, $eventref);
}

# <LJFUNC>
# name: LJ::make_remote
# des: Returns a minimal user structure ($remote-like) from
#      a username and userid.
# args: user, userid
# des-user: Username.
# des-userid: User ID.
# returns: hashref with 'user' and 'userid' keys, or undef if
#          either argument was bogus (so caller can pass
#          untrusted input)
# </LJFUNC>
sub make_remote
{
    my $user = LJ::canonical_username(shift);
    my $userid = shift;
    if ($user && $userid && $userid =~ /^\d+$/) {
        return { 'user' => $user,
                 'userid' => $userid, };
    }
    return undef;
}

# <LJFUNC>
# name: LJ::load_userids_multiple
# des: Loads a number of users at once, efficiently.
# info: loads a few users at once, their userids given in the keys of $map
#       listref (not hashref: can't have dups).  values of $map listref are
#       scalar refs to put result in.  $have is an optional listref of user
#       object caller already has, but is too lazy to sort by themselves.
# args: dbarg, map, have
# des-map: Arrayref of pairs (userid, destination scalarref)
# des-have: Arrayref of user objects caller already has
# returns: Nothing.
# </LJFUNC>
sub load_userids_multiple
{
    my ($dbarg, $map, $have) = @_;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;

    my %need;
    while (@$map) {
        my $id = shift @$map;
        my $ref = shift @$map;
        push @{$need{$id}}, $ref;
    }

    my $satisfy = sub {
        my $u = shift;
        next unless ref $u eq "HASH";
        foreach (@{$need{$u->{'userid'}}}) {
            $$_ = $u;
        }
        delete $need{$u->{'userid'}};
    };

    if ($have) {
        foreach my $u (@$have) {
            $satisfy->($u);
        }
    }

    if (keys %need) {
        my $in = join(", ", map { $_+0 } keys %need);
        ($sth = $dbr->prepare("SELECT * FROM user WHERE userid IN ($in)"))->execute;
        $satisfy->($_) while $_ = $sth->fetchrow_hashref;
    }
}

# <LJFUNC>
# name: LJ::load_user
# des: Loads a user record given a username.
# info: From the [dbarg[user]] table.
# args: dbarg, user
# des-user: Username of user to load.
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_user
{
    my $dbarg = shift;
    my $user = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $sth;

    $user = LJ::canonical_username($user);
    my $quser = $dbr->quote($user);
    my $u = $dbr->selectrow_hashref("SELECT * FROM user WHERE user=$quser");

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    if (! $u && ref $LJ::AUTH_EXISTS eq "CODE") {
        if ($LJ::AUTH_EXISTS->($user)) {
            if (LJ::create_account($dbh, {
                'user' => $user,
                'name' => $user,
                'password' => "",
            }))
            {
                # NOTE: this should pull from the master, since it was _just_
                # created and the elsif below won't catch.
                $sth = $dbh->prepare("SELECT * FROM user WHERE user=$quser");
                $sth->execute;
                $u = $sth->fetchrow_hashref;
                $sth->finish;
                return $u;
            } else {
                return undef;
            }
        }
    } elsif (! $u && $dbs->{'has_slave'}) {
        # If the user still doesn't exist, and there isn't an alternate auth code
        # try grabbing it from the master.
        $sth = $dbh->prepare("SELECT * FROM user WHERE user=$quser");
        $sth->execute;
        $u = $sth->fetchrow_hashref;
        $sth->finish;
    }

    return $u;
}

# <LJFUNC>
# name: LJ::load_userid
# des: Loads a user record given a userid.
# info: From the [dbarg[user]] table.
# args: dbarg, userid
# des-userid: Userid of user to load.
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_userid
{
    my $dbarg = shift;
    my $userid = shift;
    return undef unless $userid;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $quserid = $dbr->quote($userid);
    return LJ::dbs_selectrow_hashref($dbs, "SELECT * FROM user WHERE userid=$quserid");
}

# <LJFUNC>
# name: LJ::load_moods
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_moods
{
    return if ($LJ::CACHED_MOODS);
    my $dbarg = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT moodid, mood, parentmood FROM moods");
    $sth->execute;
    while (my ($id, $mood, $parent) = $sth->fetchrow_array) {
        $LJ::CACHE_MOODS{$id} = { 'name' => $mood, 'parent' => $parent };
        if ($id > $LJ::CACHED_MOOD_MAX) { $LJ::CACHED_MOOD_MAX = $id; }
    }
    $LJ::CACHED_MOODS = 1;
}

# <LJFUNC>
# name: LJ::query_buffer_add
# des: Schedules an insert/update query to be run on a certain table sometime
#      in the near future in a batch with a lot of similar updates, or
#      immediately if the site doesn't provide query buffering.  Returns
#      nothing (no db error code) since there's the possibility it won't
#      run immediately anyway.
# args: dbarg, table, query
# des-table: Table to modify.
# des-query: Query that'll update table.  The query <b>must not</b> access
#            any table other than that one, since the update is done inside
#            an explicit table lock for performance.
# </LJFUNC>
sub query_buffer_add
{
    my ($dbarg, $table, $query) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    if ($LJ::BUFFER_QUERIES)
    {
        # if this is a high load site, you'll want to batch queries up and send them at once.

        my $table = $dbh->quote($table);
        my $query = $dbh->quote($query);
        $dbh->do("INSERT INTO querybuffer (qbid, tablename, instime, query) VALUES (NULL, $table, NOW(), $query)");
    }
    else
    {
        # low load sites can skip this, and just have queries go through immediately.
        $dbh->do($query);
    }
}

# <LJFUNC>
# name: LJ::cmd_buffer_add
# des: Schedules some command to be run sometime in the future which would
#      be too slow to do syncronously with the web request.  An example
#      is deleting a journal entry, which requires recursing through a lot
#      of tables and deleting all the appropriate stuff.
# args: db, journalid, cmd, hargs
# des-db: Cluster master db handle to run command on.
# des-journalid: Journal id command affects.  This is indexed in the
#                [dbtable[cmdbuffer]] table so that all of a user's queued
#                actions can be run before that user is potentially moved
#                between clusters.
# des-cmd: Text of the command name.  30 chars max.
# des-hargs: Hashref of command arguments.
# </LJFUNC>
sub cmd_buffer_add
{
    my ($db, $journalid, $cmd, $h_args) = @_;

    return 0 unless $db;
    $journalid += 0;
    my $qcmd = $db->quote($cmd);
    my $qargs;
    if (ref $h_args eq "HASH") {
        foreach (sort keys %$h_args) {
            $qargs .= LJ::eurl($_) . "=" . LJ::eurl($h_args->{$_}) . "&";
        }
        chop $qargs;
    }
    $qargs = $db->quote($qargs);
    $db->do("INSERT INTO cmdbuffer (journalid, cmd, instime, args) ".
            "VALUES ($journalid, $qcmd, NOW(), $qargs)");
}

# <LJFUNC>
# name: LJ::cmd_buffer_flush
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub cmd_buffer_flush
{
    my ($dbh, $db, $cmd, $userid) = @_;
    return 0 unless $cmd;

    my $cmds = {
        'delitem' => {
            'run' => sub {
                my ($dbh, $db, $c) = @_;
                my $a = $c->{'args'};
                LJ::delete_item2($dbh, $db, $c->{'journalid'}, $a->{'itemid'},
                                 0, $a->{'anum'});
            },
        },
    };
    # TODO: call hook to augment dispatch table with site-defined commands
    return 0 unless defined $cmds->{$cmd};

    my $clist;
    my $loop = 1;
    my $cd = $cmds->{$cmd};
    my $where = "cmd=" . $dbh->quote($cmd);
    if ($userid) {
        $where .= " AND journalid=" . $dbh->quote($userid);
    }

    while ($loop &&
           ($clist = $db->selectcol_arrayref("SELECT cbid FROM cmdbuffer ".
                                             "WHERE $where ORDER BY cbid LIMIT 20")) &&
           $clist && @$clist)
    {
        foreach my $cbid (@$clist) {
            my $got_lock = $db->selectrow_array("SELECT GET_LOCK('cbid-$cbid',10)");
            return 0 unless $got_lock;
            my $c = $db->selectrow_hashref("SELECT * FROM cmdbuffer WHERE cbid=$cbid");
            next unless $c;

            my $a = {};
            LJ::decode_url_string($c->{'args'}, $a);
            $c->{'args'} = $a;
            $cmds->{$cmd}->{'run'}->($dbh, $db, $c);

            $db->do("DELETE FROM cmdbuffer WHERE cbid=$cbid");
            $db->do("SELECT RELEASE_LOCK('cbid-$cbid')");
        }
        $loop = 0 unless scalar(@$clist) == 20;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::query_buffer_flush
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub query_buffer_flush
{
    my ($dbarg, $table) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return -1 unless ($table);
    return -1 if ($table =~ /[^\w]/);

    $dbh->do("LOCK TABLES $table WRITE, querybuffer WRITE");

    my $count = 0;
    my $max = 0;
    my $qtable = $dbh->quote($table);

    # We want to leave this pointed to the master to ensure we are
    # getting the most recent data!  (also, querybuffer doesn't even
    # replicate to slaves in the recommended configuration... it's
    # pointless to do so)
    my $sth = $dbh->prepare("SELECT qbid, query FROM querybuffer WHERE tablename=$qtable ORDER BY qbid");
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }
    $sth->execute;
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }
    while (my ($id, $query) = $sth->fetchrow_array)
    {
        $dbh->do($query);
        $count++;
        $max = $id;
    }
    $sth->finish;

    $dbh->do("DELETE FROM querybuffer WHERE tablename=$qtable");
    if ($dbh->err) { $dbh->do("UNLOCK TABLES"); die $dbh->errstr; }

    $dbh->do("UNLOCK TABLES");
    return $count;
}

# <LJFUNC>
# name: LJ::journal_base
# des: Returns URL of a user's journal.
# info: The tricky thing is that users with underscores in their usernames
#       can't have some_user.site.com as a hostname, so that's changed into
#       some-user.site.com.
# args: user, vhost?
# des-user: Username of user whose URL to make.
# des-vhost: What type of URL.  Acceptable options are "users", to make a
#            http://user.site.com/ URL; "tilde" to make http://site.com/~user/;
#            "community" for http://site.com/community/user; or the default
#            will be http://site.com/users/user
# returns: scalar; a URL.
# </LJFUNC>
sub journal_base
{
    my ($user, $vhost) = @_;
    if ($vhost eq "users") {
        my $he_user = $user;
        $he_user =~ s/_/-/g;
        return "http://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
        return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
        return "$LJ::SITEROOT/community/$user";
    } else {
        return "$LJ::SITEROOT/users/$user";
    }
}

# loads all of the given privs for a given user into a hashref
# inside the user record ($u->{_privs}->{$priv}->{$arg} = 1)
# <LJFUNC>
# name: LJ::load_user_privs
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_user_privs
{
    my $dbarg = shift;
    my $remote = shift;
    my @privs = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return unless ($remote and @privs);

    # return if we've already loaded these privs for this user.
    @privs = map { $dbr->quote($_) }
             grep { ! $remote->{'_privloaded'}->{$_}++ } @privs;

    return unless (@privs);

    my $sth = $dbr->prepare("SELECT pl.privcode, pm.arg ".
                            "FROM priv_map pm, priv_list pl ".
                            "WHERE pm.prlid=pl.prlid AND ".
                            "pl.privcode IN (" . join(',',@privs) . ") ".
                            "AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    while (my ($priv, $arg) = $sth->fetchrow_array)
    {
        unless (defined $arg) { $arg = ""; }  # NULL -> ""
        $remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}

# <LJFUNC>
# name: LJ::check_priv
# des: Check to see if a user has a certain privilege.
# info: Usually this is used to check the privs of a $remote user.
#       See [func[LJ::get_remote]].  As such, a $u argument of undef
#       is okay to pass: 0 will be returned, as an unknown user can't
#       have any rights.
# args: dbarg, u, priv, arg?
# des-priv: Priv name to check for (see [dbtable[priv_list]])
# des-arg: Optional argument.  If defined, function only returns true
#          when $remote has a priv of type $priv also with arg $arg, not
#          just any priv of type $priv, which is the behavior without
#          an $arg
# returns: boolean; true if user has privilege
# </LJFUNC>
sub check_priv
{
    my ($dbarg, $u, $priv, $arg) = @_;
    return 0 unless $u;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    if (! $u->{'_privloaded'}->{$priv}) {
        if ($dbr) {
            load_user_privs($dbr, $u, $priv);
        } else {
            return 0;
        }
    }

    if (defined $arg) {
        return (defined $u->{'_priv'}->{$priv} &&
                defined $u->{'_priv'}->{$priv}->{$arg});
    } else {
        return (defined $u->{'_priv'}->{$priv});
    }
}

#
#
# <LJFUNC>
# name: LJ::remote_has_priv
# class:
# des: Check to see if the given remote user has a certain priviledge
# info: DEPRECATED.  should use load_user_privs + check_priv
# args:
# des-:
# returns:
# </LJFUNC>
sub remote_has_priv
{
    my $dbarg = shift;
    my $remote = shift;
    my $privcode = shift;     # required.  priv code to check for.
    my $ref = shift;  # optional, arrayref or hashref to populate

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    return 0 unless ($remote);

    ### authentication done.  time to authorize...

    my $qprivcode = $dbh->quote($privcode);
    my $sth = $dbr->prepare("SELECT pm.arg FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode=$qprivcode AND pm.userid=$remote->{'userid'}");
    $sth->execute;

    my $match = 0;
    if (ref $ref eq "ARRAY") { @$ref = (); }
    if (ref $ref eq "HASH") { %$ref = (); }
    while (my ($arg) = $sth->fetchrow_array) {
        $match++;
        if (ref $ref eq "ARRAY") { push @$ref, $arg; }
        if (ref $ref eq "HASH") { $ref->{$arg} = 1; }
    }
    return $match;
}

# <LJFUNC>
# name: LJ::get_userid
# des: Returns a userid given a username.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_username]].
# args: dbarg, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_userid
{
    my $dbarg = shift;
    my $user = shift;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $user = canonical_username($user);

    my $userid;
    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $quser = $dbr->quote($user);
    my $sth = $dbr->prepare("SELECT userid FROM useridmap WHERE user=$quser");
    $sth->execute;
    ($userid) = $sth->fetchrow_array;
    if ($userid) { $LJ::CACHE_USERID{$user} = $userid; }

    # implictly create an account if we're using an external
    # auth mechanism
    if (! $userid && ref $LJ::AUTH_EXISTS eq "CODE")
    {
        # TODO: eventual $dbs conversion (even though create_account will ALWAYS
        # use the master)
        $userid = LJ::create_account($dbh, { 'user' => $user,
                                             'name' => $user,
                                             'password' => '', });
    }

    return ($userid+0);
}

# <LJFUNC>
# name: LJ::get_username
# des: Returns a username given a userid.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_userid]].
# args: dbarg, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_username
{
    my $dbarg = shift;
    my $userid = shift;
    my $user;
    $userid += 0;

    # Checked the cache first.
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT user FROM useridmap WHERE userid=$userid");
    $sth->execute;
    $user = $sth->fetchrow_array;

    # Fall back to master if it doesn't exist.
    if (! defined($user) && $dbs->{'has_slave'}) {
        my $dbh = $dbs->{'dbh'};
        $sth = $dbh->prepare("SELECT user FROM useridmap WHERE userid=$userid");
        $sth->execute;
        $user = $sth->fetchrow_array;
    }
    if (defined($user)) { $LJ::CACHE_USERNAME{$userid} = $user; }
    return ($user);
}

# <LJFUNC>
# name: LJ::get_itemid_near
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_itemid_near
{
    my $dbarg = shift;
    my $itemid = shift;
    my $after_before = shift;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my ($inc, $order);
    if ($after_before eq "after") {
        ($inc, $order) = (-1, "DESC");
    } elsif ($after_before eq "before") {
        ($inc, $order) = (1, "ASC");
    } else {
        return 0;
    }

    $itemid += 0;
    my $lr = $dbr->selectrow_hashref("SELECT u.userid, u.journaltype, l.rlogtime, l.revttime ".
                                     "FROM user u, log l WHERE l.itemid=$itemid ".
                                     "AND l.ownerid=u.userid");
    return 0 unless $lr;
    my $jid = $lr->{'userid'};
    my $field = $lr->{'journaltype'} eq "P" ? "revttime" : "rlogtime";
    my $stime = $lr->{$field};

    my $day = 86400;
    foreach my $distance ($day, $day*7, $day*30, $day*90) {
        my ($one_away, $further) = ($stime + $inc, $stime + $inc*$distance);
        if ($further < $one_away) {
            # swap them, BETWEEN needs lower number first
            ($one_away, $further) = ($further, $one_away);
        }
        my ($id, $anum) =
            $dbr->selectrow_array("SELECT itemid FROM log WHERE ownerid=$jid ".
                                  "AND $field BETWEEN $one_away AND $further ".
                                  "ORDER BY $field $order LIMIT 1");
        return $id if $id;
    }
    return 0;
}


# <LJFUNC>
# name: LJ::get_itemid_after
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_itemid_after  { return get_itemid_near(@_, "after");  }
# <LJFUNC>
# name: LJ::get_itemid_before
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_itemid_before { return get_itemid_near(@_, "before"); }


sub get_itemid_near2
{
    my $u = shift;
    my $jitemid = shift;
    my $after_before = shift;

    $jitemid += 0;

    my ($inc, $order);
    if ($after_before eq "after") {
        ($inc, $order) = (-1, "DESC");
    } elsif ($after_before eq "before") {
        ($inc, $order) = (1, "ASC");
    } else {
        return 0;
    }

    my $dbr = LJ::get_cluster_reader($u);
    my $jid = $u->{'userid'}+0;
    my $field = $u->{'journaltype'} eq "P" ? "revttime" : "rlogtime";

    my $stime = $dbr->selectrow_array("SELECT $field FROM log2 WHERE ".
                                      "journalid=$jid AND jitemid=$jitemid");
    return 0 unless $stime;


    my $day = 86400;
    foreach my $distance ($day, $day*7, $day*30, $day*90) {
        my ($one_away, $further) = ($stime + $inc, $stime + $inc*$distance);
        if ($further < $one_away) {
            # swap them, BETWEEN needs lower number first
            ($one_away, $further) = ($further, $one_away);
        }
        my ($id, $anum) =
            $dbr->selectrow_array("SELECT jitemid, anum FROM log2 WHERE journalid=$jid ".
                                  "AND $field BETWEEN $one_away AND $further ".
                                  "ORDER BY $field $order LIMIT 1");
        if ($id) {
            return wantarray() ? ($id, $anum) : ($id*256 + $anum);
        }
    }
    return 0;
}

sub get_itemid_after2  { return get_itemid_near2(@_, "after");  }
sub get_itemid_before2 { return get_itemid_near2(@_, "before"); }


# <LJFUNC>
# name: LJ::mysql_time
# des:
# class: time
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub mysql_time
{
    my $time = shift;
    $time ||= time();
    my @ltime = localtime($time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $ltime[5]+1900,
                   $ltime[4]+1,
                   $ltime[3],
                   $ltime[2],
                   $ltime[1],
                   $ltime[0]);
}

# <LJFUNC>
# name: LJ::get_keyword_id
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_keyword_id
{
    my $dbarg = shift;
    my $kw = shift;
    unless ($kw =~ /\S/) { return 0; }
    $kw = LJ::text_trim($kw, $LJ::BMAX_KEYWORD, $LJ::CMAX_KEYWORD);

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $qkw = $dbh->quote($kw);

    # Making this a $dbr could cause problems due to the insertion of
    # data based on the results of this query. Leave as a $dbh.
    my $sth = $dbh->prepare("SELECT kwid FROM keywords WHERE keyword=$qkw");
    $sth->execute;
    my ($kwid) = $sth->fetchrow_array;
    unless ($kwid) {
        $sth = $dbh->prepare("INSERT INTO keywords (kwid, keyword) VALUES (NULL, $qkw)");
        $sth->execute;
        $kwid = $dbh->{'mysql_insertid'};
    }
    return $kwid;
}

# <LJFUNC>
# name: LJ::trim
# class: text
# des: Removes whitespace from left and right side of a string.
# args: string
# des-string: string to be trimmed
# returns: string trimmed
# </LJFUNC>
sub trim
{
    my $a = $_[0];
    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    return $a;
}

# returns true if $formref->{'password'} matches cleartext password or if
# $formref->{'hpassword'} is the hash of the cleartext password
# DEPRECTED: should use LJ::auth_okay
# <LJFUNC>
# name: LJ::valid_password
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub valid_password
{
    my ($clearpass, $formref) = @_;
    if ($formref->{'password'} && $formref->{'password'} eq $clearpass)
    {
        return 1;
    }
    if ($formref->{'hpassword'} && lc($formref->{'hpassword'}) eq &hash_password($clearpass))
    {
        return 1;
    }
    return 0;
}

# <LJFUNC>
# name: LJ::delete_user
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub delete_user
{
                # TODO: Is this function even being called?
                # It doesn't look like it does anything useful
    my $dbh = shift;
    my $user = shift;
    my $quser = $dbh->quote($user);
    my $sth;
    $sth = $dbh->prepare("SELECT user, userid FROM useridmap WHERE user=$quser");
    my $u = $sth->fetchrow_hashref;
    unless ($u) { return; }

    ### so many issues.
}

# <LJFUNC>
# name: LJ::hash_password
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub hash_password
{
    return Digest::MD5::md5_hex($_[0]);
}

# $dbarg can be either a $dbh (master) or a $dbs (db set, master & slave hashref)
# <LJFUNC>
# name: LJ::can_use_journal
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub can_use_journal
{
    my ($dbarg, $posterid, $reqownername, $res) = @_;

    my $dbs = LJ::make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $qposterid = $posterid+0;

    ## find the journal owner's info
    my $uowner = LJ::load_user($dbs, $reqownername);
    unless ($uowner) {
        $res->{'errmsg'} = "Journal \"$reqownername\" does not exist.";
        return 0;
    }
    my $ownerid = $uowner->{'userid'};

    ## check if user has access
    my $sql = "SELECT COUNT(*) FROM logaccess WHERE ownerid=$ownerid AND posterid=$qposterid";
    if ($dbr->selectrow_array($sql) || $dbh->selectrow_array($sql))
    {
        # the 'ownerid' necessity came first, way back when.  but then
        # with clusters, everything needed to know more, like the
        # journal's dversion and clusterid, so now it also returns the
        # user row.
        $res->{'ownerid'} = $ownerid;
        $res->{'u_owner'} = $uowner;
        return 1;
    } else {
        $res->{'errmsg'} = "You do not have access to post to this journal.";
        return 0;
    }
}

# <LJFUNC>
# name: LJ::load_log_props
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_log_props
{
    my ($dbarg, $listref, $hashref) = @_;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbr = $dbs->{'reader'};

    my $itemin = join(", ", map { $_+0; } @{$listref});
    unless ($itemin) { return ; }
    unless (ref $hashref eq "HASH") { return; }

    my $sth = $dbr->prepare("SELECT p.itemid, l.name, p.value ".
                            "FROM logprop p, logproplist l ".
                            "WHERE p.propid=l.propid AND p.itemid IN ($itemin)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        $hashref->{$_->{'itemid'}}->{$_->{'name'}} = $_->{'value'};
    }
}

# Note: requires caller to first call LJ::load_props($dbs, "log")
# <LJFUNC>
# name: LJ::load_log_props2
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_log_props2
{
    my ($db, $journalid, $listref, $hashref) = @_;

    my $jitemin = join(", ", map { $_+0; } @$listref);
    return unless $jitemin;
    return unless ref $hashref eq "HASH";
    return unless defined $LJ::CACHE_PROPID{'log'};

    my $sth = $db->prepare("SELECT jitemid, propid, value FROM logprop2 ".
                           "WHERE journalid=$journalid AND jitemid IN ($jitemin)");
    $sth->execute;
    while (my ($jitemid, $propid, $value) = $sth->fetchrow_array) {
        $hashref->{$jitemid}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
    }
}

# Note: requires caller to first call LJ::load_props($dbs, "log")
# <LJFUNC>
# name: LJ::load_log_props2multi
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_log_props2multi
{
    # ids by cluster (hashref),  output hashref (keys = "$ownerid $jitemid",
    # where ownerid could be 0 for unclustered)
    my ($dbs, $idsbyc, $hashref) = @_;
    my $sth;
    return unless ref $idsbyc eq "HASH";
    return unless defined $LJ::CACHE_PROPID{'log'};

    foreach my $c (keys %$idsbyc)
    {
        if ($c) {
            # clustered:
            my $fattyin = join(" OR ", map {
                "(journalid=" . ($_->[0]+0) . " AND jitemid=" . ($_->[1]+0) . ")"
            } @{$idsbyc->{$c}});
            my $db = LJ::get_cluster_reader($c);
            $sth = $db->prepare("SELECT journalid, jitemid, propid, value ".
                                "FROM logprop2 WHERE $fattyin");
            $sth->execute;
            while (my ($jid, $jitemid, $propid, $value) = $sth->fetchrow_array) {
                $hashref->{"$jid $jitemid"}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
            }
        } else {
            # unclustered:
            my $dbr = $dbs->{'reader'};
            my $in = join(",", map { $_+0 } @{$idsbyc->{'0'}});
            $sth = $dbr->prepare("SELECT itemid, propid, value FROM logprop ".
                                 "WHERE itemid IN ($in)");
            $sth->execute;
            while (my ($itemid, $propid, $value) = $sth->fetchrow_array) {
                $hashref->{"0 $itemid"}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
            }

        }
    }
    foreach my $c (keys %$idsbyc)
    {
        if ($c) {
            # clustered:
            my $fattyin = join(" OR ", map {
                "(journalid=" . ($_->[0]+0) . " AND jitemid=" . ($_->[1]+0) . ")"
            } @{$idsbyc->{$c}});
            my $db = LJ::get_cluster_reader($c);
            $sth = $db->prepare("SELECT journalid, jitemid, propid, value ".
                                "FROM logprop2 WHERE $fattyin");
            $sth->execute;
            while (my ($jid, $jitemid, $propid, $value) = $sth->fetchrow_array) {
                $hashref->{"$jid $jitemid"}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
            }
        } else {
            # unclustered:
            my $dbr = $dbs->{'reader'};
            my $in = join(",", map { $_+0 } @{$idsbyc->{'0'}});
            $sth = $dbr->prepare("SELECT itemid, propid, value FROM logprop ".
                                 "WHERE itemid IN ($in)");
            $sth->execute;
            while (my ($itemid, $propid, $value) = $sth->fetchrow_array) {
                $hashref->{"0 $itemid"}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
            }

        }
    }
}

# <LJFUNC>
# name: LJ::load_talk_props
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_talk_props
{
    my ($dbarg, $listref, $hashref) = @_;
    my $itemin = join(", ", map { $_+0; } @{$listref});
    unless ($itemin) { return ; }
    unless (ref $hashref eq "HASH") { return; }

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    my $sth = $dbr->prepare("SELECT tp.talkid, tpl.name, tp.value ".
                            "FROM talkproplist tpl, talkprop tp ".
                            "WHERE tp.tpropid=tpl.tpropid ".
                            "AND tp.talkid IN ($itemin)");
    $sth->execute;
    while (my ($id, $name, $val) = $sth->fetchrow_array) {
        $hashref->{$id}->{$name} = $val;
    }
}

# Note: requires caller to first call LJ::load_props($dbs, "talk")
# <LJFUNC>
# name: LJ::load_talk_props2
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_talk_props2
{
    my ($db, $journalid, $listref, $hashref) = @_;

    my $in = join(", ", map { $_+0; } @$listref);
    return unless $in;
    die "Last param not hash" unless ref $hashref eq "HASH";
    die "talkprops not loaded" unless defined $LJ::CACHE_PROPID{'talk'};

    my $sth = $db->prepare("SELECT jtalkid, tpropid, value FROM talkprop2 ".
                           "WHERE journalid=$journalid AND jtalkid IN ($in)");
    $sth->execute;
    while (my ($jtalkid, $propid, $value) = $sth->fetchrow_array) {
        my $p = $LJ::CACHE_PROPID{'talk'}->{$propid};
        next unless $p;
        $hashref->{$jtalkid}->{$p->{'name'}} = $value;
    }
}

# <LJFUNC>
# name: LJ::eurl
# class: text
# des: Escapes a value before it can be put in a URL.  See also [func[LJ::durl]].
# args: string
# des-string: string to be escaped
# returns: string escaped
# </LJFUNC>
sub eurl
{
    my $a = $_[0];
    $a =~ s/([^a-zA-Z0-9_\,\-.\/\\\: ])/uc sprintf("%%%02x",ord($1))/eg;
    $a =~ tr/ /+/;
    return $a;
}

# <LJFUNC>
# name: LJ::durl
# class: text
# des: Decodes a value that's URL-escaped.  See also [func[LJ::eurl]].
# args: string
# des-string: string to be decoded
# returns: string decoded
# </LJFUNC>
sub durl
{
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

# <LJFUNC>
# name: LJ::exml
# class: text
# des: Escapes a value before it can be put in XML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub exml
{
    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}

# <LJFUNC>
# name: LJ::ehtml
# class: text
# des: Escapes a value before it can be put in HTML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ehtml
{
    my $a = $_[0];
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&\#39;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    return $a;
}


# <LJFUNC>
# name: LJ::eall
# class: text
# des: Escapes HTML and BML.
# args: text
# des-text: Text to escape.
# returns: Escaped text.
# </LJFUNC>
sub eall
{
    my $a = shift;

    ### escape HTML
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;

    ### and escape BML
    $a =~ s/\(=/\(&\#0061;/g;
    $a =~ s/=\)/&\#0061;\)/g;
    return $a;
}

# <LJFUNC>
# name: LJ::days_in_month
# class: time
# des: Figures out the number of days in a month.
# args: month, year?
# des-month: Month
# des-year: Year.  Necessary for February.  If undefined or zero, function
#           will return 29.
# returns: Number of days in that month in that year.
# </LJFUNC>
sub days_in_month
{
    my ($month, $year) = @_;
    if ($month == 2)
    {
        return 29 unless $year;  # assume largest
        if ($year % 4 == 0)
        {
          # years divisible by 400 are leap years
          return 29 if ($year % 400 == 0);

          # if they're divisible by 100, they aren't.
          return 28 if ($year % 100 == 0);

          # otherwise, if divisible by 4, they are.
          return 29;
        }
    }
    return ((31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$month-1]);
}

# <LJFUNC>
# name: LJ::delete_item
# des: Deletes a journal item from a user's journal that resides in the old schema (cluster0).
# info: This function is deprecated, just as the old schema is deprecated.  In a
#       few months this function will be removed.  The new equivalent to this
#       function is [func[LJ::delete_item2]].
# args: dbarg, journalid, itemid, quick?, deleter?
# des-journalid: Userid of journal to delete item from.
# des-itemid: Itemid of item to delete.
# des-quick: Optional flag to make the delete be a little quicker when many deletes
#            are occuring.  It just doesn't update lastitemid in [dbtable[userusage]].
# des-deleter: Optional code reference to run to handle a deletion.  Mass-delete
#              tools can use this to batch deletes in table locks for speed.  Arguments
#              to this coderef are ($tablename, $col, @ids).  The default implementation
#              is: "DELETE FROM $table WHERE $col IN (@ids)"
# returns:
# </LJFUNC>
sub delete_item
{
    my ($dbarg, $ownerid, $itemid, $quick, $deleter) = @_;
    my $sth;

    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    $ownerid += 0;
    $itemid += 0;

    $deleter ||= sub {
        my $table = shift;
        my $col = shift;
        my @ids = @_;
        return unless @ids;
        my $in = join(",", @ids);
        $dbh->do("DELETE FROM $table WHERE $col IN ($in)");
    };

    $deleter->("memorable", "itemid", $itemid);
    $dbh->do("UPDATE userusage SET lastitemid=0 WHERE userid=$ownerid AND lastitemid=$itemid") unless ($quick);
    foreach my $t (qw(log logtext logsubject logprop)) {
        $deleter->($t, "itemid", $itemid);
    }
    $dbh->do("DELETE FROM logsec WHERE ownerid=$ownerid AND itemid=$itemid");

    my @talkids = ();
    $sth = $dbh->prepare("SELECT talkid FROM talk WHERE nodetype='L' AND nodeid=$itemid");
    $sth->execute;
    push @talkids, $_ while ($_ = $sth->fetchrow_array);
    foreach my $t (qw(talk talktext talkprop)) {
        $deleter->($t, "talkid", @talkids);
    }
}

# <LJFUNC>
# name: LJ::delete_item2
# des: Deletes a user's journal item from a cluster.
# args: dbh, dbcm, journalid, jitemid, quick?, anum?
# des-journalid: Journal ID item is in.
# des-jitemid: Journal itemid of item to delete.
# des-quick: Optional boolean.  If set, only [dbtable[log2]] table
#            is deleted from and the rest of the content is deleted
#            later using [func[LJ::cmd_buffer_add]].
# des-anum: The log item's anum, which'll be needed to delete lazily
#           some data in tables which includes the anum, but the
#           log row will already be gone so we'll need to store it for later.
# returns: boolean; 1 on success, 0 on failure.
# </LJFUNC>
sub delete_item2
{
    my ($dbh, $dbcm, $jid, $jitemid, $quick, $anum) = @_;
    $jid += 0; $jitemid += 0;

    $dbcm->do("DELETE FROM log2 WHERE journalid=$jid AND jitemid=$jitemid");

    return LJ::cmd_buffer_add($dbcm, $jid, "delitem", {
        'itemid' => $jitemid,
        'anum' => $anum,
    }) if $quick;

    # delete from clusters
    foreach my $t (qw(logtext2 logprop2 logsec2 logsubject2)) {
        $dbcm->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$jitemid");
    }
    LJ::dudata_set($dbcm, $jid, 'L', $jitemid, 0);

    # delete stuff from meta cluster
    my $aitemid = $jitemid * 256 + $anum;
    foreach my $t (qw(memorable topic_map)) {
        $dbh->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$aitemid");
    }

    # delete comments
    my ($t, $loop) = (undef, 1);
    while ($loop &&
           ($t = $dbcm->selectcol_arrayref("SELECT jtalkid FROM talk2 WHERE ".
                                           "nodetype='L' AND journalid=$jid ".
                                           "AND nodeid=$jitemid LIMIT 50"))
           && $t && @$t)
    {
        foreach my $jtalkid (@$t) {
            LJ::delete_talkitem($dbcm, $jid, $jtalkid);
        }
        $loop = 0 unless @$t == 50;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::delete_talkitem
# des: Deletes a comment and associated metadata.
# info: The tables [dbtable[talk2]], [dbtabke[talkprop2]], [dbtable[talktext2]],
#       and [dbtable[dudata]] are all
#       deleted from, immediately. Unlike [func[LJ::delete_item2]], there is
#       no $quick flag to queue the delete for later, nor is one really
#       necessary, since deleting from 4 tables won't be too slow.
# args: dbcm, journalid, jtalkid, light?
# des-journalid: Journalid (userid from [dbtable[user]] to delete comment from).
#                The journal must reside on the $dbcm you provide.
# des-jtalkid: The jtalkid of the comment.
# des-dbcm: Cluster master db to delete item from.
# des-light: boolean; if true, only mark entry as deleted, so children will thread.
# returns: boolean; 1 on success, 0 on failure.# des-dbh: Master database handle.
# </LJFUNC>
sub delete_talkitem
{
    my ($dbcm, $jid, $jtalkid, $light) = @_;
    $jid += 0; $jtalkid += 0;

    my $where = "WHERE journalid=$jid AND jtalkid=$jtalkid";
    my @delfrom = qw(talkprop2);
    if ($light) {
        $dbcm->do("UPDATE talk2 SET state='D' $where");
        $dbcm->do("UPDATE talktext2 SET subject=NULL, body=NULL $where");
    } else {
        push @delfrom, qw(talk2 talktext2);
    }

    foreach my $t (@delfrom) {
        $dbcm->do("DELETE FROM $t $where");
        return 0 if $dbcm->err;
    }
    LJ::dudata_set($dbcm, $jid, 'T', $jtalkid, 0);
    return 0 if $dbcm->err;
    return 1;
}

# <LJFUNC>
# name: LJ::alldateparts_to_hash
# class: s1
# des: Given a date/time format from MySQL, breaks it into a hash.
# info: This is used by S1.
# args: alldatepart
# des-alldatepart: The output of the MySQL function
#                  DATE_FORMAT(sometime, "%a %W %b %M %y %Y %c %m %e %d
#                  %D %p %i %l %h %k %H")
# returns: Hash (whole, not reference), with keys: dayshort, daylong,
#          monshort, monlong, yy, yyyy, m, mm, d, dd, dth, ap, AP,
#          ampm, AMPM, min, 12h, 12hh, 24h, 24hh

# </LJFUNC>
sub alldateparts_to_hash
{
    my $alldatepart = shift;
    my @dateparts = split(/ /, $alldatepart);
    return (
            'dayshort' => $dateparts[0],
            'daylong' => $dateparts[1],
            'monshort' => $dateparts[2],
            'monlong' => $dateparts[3],
            'yy' => $dateparts[4],
            'yyyy' => $dateparts[5],
            'm' => $dateparts[6],
            'mm' => $dateparts[7],
            'd' => $dateparts[8],
            'dd' => $dateparts[9],
            'dth' => $dateparts[10],
            'ap' => substr(lc($dateparts[11]),0,1),
            'AP' => substr(uc($dateparts[11]),0,1),
            'ampm' => lc($dateparts[11]),
            'AMPM' => $dateparts[11],
            'min' => $dateparts[12],
            '12h' => $dateparts[13],
            '12hh' => $dateparts[14],
            '24h' => $dateparts[15],
            '24hh' => $dateparts[16],
            );
}

# <LJFUNC>
# name: LJ::dudata_set
# class: logging
# des: Record or delete disk usage data for a journal
# args: dbcm, journalid, area, areaid, bytes
# journalid: Journal userid to record space for.
# area: One character: "L" for log, "T" for talk, "B" for bio, "P" for pic.
# areaid: Unique ID within $area, or '0' if area has no ids (like bio)
# bytes: Number of bytes item takes up.  Or 0 to delete record.
# returns: 1.
# </LJFUNC>
sub dudata_set
{
    my ($dbcm, $journalid, $area, $areaid, $bytes) = @_;
    $bytes += 0; $areaid += 0; $journalid += 0;
    $area = $dbcm->quote($area);
    if ($bytes) {
        $dbcm->do("REPLACE INTO dudata (userid, area, areaid, bytes) ".
                  "VALUES ($journalid, $area, $areaid, $bytes)");
    } else {
        $dbcm->do("DELETE FROM dudata WHERE userid=$journalid AND ".
                  "area=$area AND areaid=$areaid");
    }
    return 1;
}

# <LJFUNC>
# name: LJ::color_fromdb
# des: Takes a value of unknown type from the db and returns an #rrggbb string.
# args: color
# des-color: either a 24-bit decimal number, or an #rrggbb string.
# returns: scalar; #rrggbb string, or undef if unknown input format
# </LJFUNC>
sub color_fromdb
{
    my $c = shift;
    return $c if $c =~ /^\#[0-9a-f]{6,6}$/i;
    return sprintf("\#%06x", $c) if $c =~ /^\d+$/;
    return undef;
}

# <LJFUNC>
# name: LJ::color_todb
# des: Takes an #rrggbb value and returns a 24-bit decimal number.
# args: color
# des-color: scalar; an #rrggbb string.
# returns: undef if bogus color, else scalar; 24-bit decimal number, can be up to 8 chars wide as a string.
# </LJFUNC>
sub color_todb
{
    my $c = shift;
    return undef unless $c =~ /^\#[0-9a-f]{6,6}$/i;
    return hex(substr($c, 1, 6));
}

# <LJFUNC>
# name: LJ::add_friend
# des: Simple interface to add a friend edge.
# args: dbh, userida, useridb
# des-userida: Userid of source user (befriender)
# des-useridb: Userid of target user (befriendee)
# returns: boolean; 1 on success (or already friend), 0 on failure (bogus args)
# </LJFUNC>
sub add_friend
{
    my ($dbh, $ida, $idb) = @_;
    return 0 unless $dbh;
    return 0 unless $ida =~ /^\d+$/ && $ida;
    return 0 unless $idb =~ /^\d+$/ && $idb;
    my $black = LJ::color_todb("#000000");
    my $white = LJ::color_todb("#ffffff");
    $dbh->do("INSERT INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) ".
             "VALUES ($ida, $idb, $black, $white, 1)");
    return 1;
}

# <LJFUNC>
# name: LJ::event_register
# des: Logs a subscribable event, if anybody's subscribed to it.
# args: dbarg, dbc, etype, ejid, eiarg, duserid, diarg
# des-dbc: Cluster master of event
# des-type: One character event type.
# des-ejid: Journalid event occured in.
# des-eiarg: 4 byte numeric argument
# des-duserid: Event doer's userid
# des-diarg: Event's 4 byte numeric argument
# returns: boolean; 1 on success; 0 on fail.
# </LJFUNC>
sub event_register
{
    my ($dbarg, $dbc, $etype, $ejid, $eiarg, $duserid, $diarg) = @_;
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};

    # see if any subscribers first of all (reads cheap; writes slow)
    return 0 unless $dbr;
    my $qetype = $dbr->quote($etype);
    my $qejid = $ejid+0;
    my $qeiarg = $eiarg+0;
    my $qduserid = $duserid+0;
    my $qdiarg = $diarg+0;

    my $has_sub = $dbr->selectrow_array("SELECT userid FROM subs WHERE etype=$qetype AND ".
                                        "ejournalid=$qejid AND eiarg=$qeiarg LIMIT 1");
    return 1 unless $has_sub;

    # so we're going to need to log this event
    return 0 unless $dbc;
    $dbc->do("INSERT INTO events (evtime, etype, ejournalid, eiarg, duserid, diarg) ".
             "VALUES (NOW(), $qetype, $qejid, $qeiarg, $qduserid, $qdiarg)");
    return $dbc->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::is_ascii
# des: checks if text is pure ASCII
# args: text
# des-text: text to check for being pure 7-bit ASCII text
# returns: 1 if text is indeed pure 7-bit, 0 otherwise.
# </LJFUNC>
sub is_ascii {
    my $text = shift;
    return ($text !~ m/[\x00\x80-\xff]/);
}

# <LJFUNC>
# name: LJ::is_utf8
# des: check text for UTF-8 validity
# args: text
# des-text: text to check for UTF-8 validity
# returns: 1 if text is a valid UTF-8 stream, 0 otherwise.
# </LJFUNC>
sub is_utf8 {
    my $text = shift;

    $text =~ m/^([\x00-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xef][\x80-\xbf][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf])*(.*)/;

    return 1 unless $2;
    return 0;
}

# <LJFUNC>
# name: LJ::text_out
# des: force outgoing text into valid UTF-8
# args: text
# des-text: reference to text to pass to output. Text if modified in-place.
# returns: nothing.
# </LJFUNC>
sub text_out
{
    my $rtext = shift;

    # if we're not Unicode, do nothing
    return unless $LJ::UNICODE;

    # is this valid UTF-8 already?
    return if LJ::is_utf8($$rtext);

    # no. Blot out all non-ASCII chars
    $$rtext =~ s/[\x00\x80-\xff]/\?/g;
    return;
}

# <LJFUNC>
# name: LJ::text_in
# des: do appropriate checks on input text. Should be called on all
#      user-generated text.
# args: text
# des-text: text to check
# returns: 1 if the text is valid, 0 if not.
# </LJFUNC>
sub text_in
{
    my $text = shift;
    return 1 unless $LJ::UNICODE;
    if (ref ($text) eq "HASH") {
        return ! (grep { !LJ::is_utf8($_) } values %{$text});
    }
    return LJ::is_utf8($text);
}

# <LJFUNC>
# name: LJ::text_convert
# des: convert old entries/comments to UTF-8 using user's default encoding
# args: dbs, text, u, error
# des-text: old possibly non-ASCII text to convert
# des-u: user hashref of the journal's owner
# des-error: ref to a scalar variable which is set to 1 on error 
#            (when user has no default encoding defined, but 
#            text needs to be translated)
# returns: converted text or undef on error
# </LJFUNC>
sub text_convert
{
    my ($dbs, $text, $u, $error) = @_;

    # maybe it's pure ASCII?
    return $text if LJ::is_ascii($text);

    # load encoding id->name mapping if it's not loaded yet
    LJ::load_codes($dbs, { "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;

    if ($u->{'oldenc'} == 0 ||
        not defined $LJ::CACHE_ENCODINGS{$u->{'oldenc'}}) {
        $$error = 1;
        return undef;
    };

    # convert!
    my $name = $LJ::CACHE_ENCODINGS{$u->{'oldenc'}};
    unless (Unicode::MapUTF8::utf8_supported_charset($name)) {
        $$error = 1;
        return undef;
    }

    return Unicode::MapUTF8::to_utf8({-string=>$text, -charset=>$name});
}


# <LJFUNC>
# name: LJ::text_trim
# des: truncate string according to requirements on byte length, char
#      length, or both. "char length" means number of UTF-8 characters if
#      $LJ::UNICODE is set, or the same thing as byte length otherwise.
# args: text, byte_max, char_max
# des-text: the string to trim
# des-byte_max: maximum allowed length in bytes; if 0, there's no restriction
# des-char_max: maximum allowed length in chars; if 0, there's no restriction
# returns: the truncated string.
sub text_trim
{
    my ($text, $byte_max, $char_max) = @_;
    return $text unless $byte_max or $char_max;
    if ($char_max == 0 || !$LJ::UNICODE) {
        $byte_max = $char_max if $char_max and $char_max < $byte_max;
        $byte_max = $char_max unless $byte_max;
        return substr($text, 0, $byte_max);
    }
    my $cur = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    while ($text =~ m/$utf_char/gco) {
	last unless $char_max;
        last if $cur + length($1) > $byte_max and $byte_max;
        $cur += length($1);
        $char_max--;
    }
    return substr($text,0,$cur);
}

# <LJFUNC>
# name: LJ::item_toutf8
# des: convert one item's subject, text and props to UTF8.
#      item can be an entry or a comment (in which cases props can be
#      left empty, since there are no 8bit talkprops).
# args: dbs, u, subject, text, props
# des-u: user hashref of the journal's owner
# des-subject: ref to the item's subject
# des-text: ref to the item's text
# des-props: hashref of the item's props
# returns: nothing.
sub item_toutf8
{
    my ($dbs, $u, $subject, $text, $props) = @_;
    return unless $LJ::UNICODE;

    my $convert = sub {
        my $rtext = shift;
        my $error = 0;
        my $res = LJ::text_convert($dbs, $$rtext, $u, \$error);
        if ($error) {
	    LJ::text_out($rtext);
        } else {
            $$rtext = $res;
        };
        return;
    };

    $convert->($subject);
    $convert->($text);
    foreach(keys %$props) {
        $convert->(\$props->{$_});
    }
    return;
}

1;
