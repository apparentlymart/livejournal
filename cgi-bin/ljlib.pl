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

package LJ;

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use DBI;
use DBI::Role;
use Digest::MD5 ();
use MIME::Lite ();
use HTTP::Date ();
use LJ::MemCache;
use Time::Local ();
use Storable ();

do "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
do "$ENV{'LJHOME'}/cgi-bin/ljdefaults.pl";

require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
require "$ENV{'LJHOME'}/cgi-bin/htmlcontrols.pl";

eval { require "$ENV{'LJHOME'}/cgi-bin/ljlib-local.pl"; };

# determine how we're going to send mail
$LJ::OPTMOD_NETSMTP = eval "use Net::SMTP (); 1;";

if ($LJ::SMTP_SERVER) {
    die "Net::SMTP not installed\n" unless $LJ::OPTMOD_NETSMTP;
    MIME::Lite->send('smtp', $LJ::SMTP_SERVER, Timeout => 10);
} else {
    MIME::Lite->send('sendmail', $LJ::SENDMAIL);
}

$LJ::DBIRole = new DBI::Role {
    'timeout' => $LJ::DB_TIMEOUT,
    'sources' => \%LJ::DBINFO,
    'weights_from_db' => $LJ::DBWEIGHTS_FROM_DB,
    'default_db' => "livejournal",
    'messages_to' => \&procnotify_callback,
    'time_check' => 60,
    'time_report' => \&dbtime_callback,
};

# $LJ::PROTOCOL_VER is the version of the client-server protocol
# used uniformly by server code which uses the protocol.
$LJ::PROTOCOL_VER = ($LJ::UNICODE ? "1" : "0");

# user.dversion values:
#    0: unclustered  (unsupported)
#    1: clustered, not pics (unsupported)
#    2: clustered
#    3: weekuserusage populated
#    4: userproplite2 clustered, and cldversion on userproplist table
$LJ::MAX_DVERSION = 4;

# constants
use constant ENDOFTIME => 2147483647;
$LJ::EndOfTime = 2147483647;  # for string interpolation

# width constants. BMAX_ constants are restrictions on byte width,
# CMAX_ on character width (character means byte unless $LJ::UNICODE,
# in which case it means a UTF-8 character).

use constant BMAX_SUBJECT => 255; # *_SUBJECT for journal events, not comments
use constant CMAX_SUBJECT => 100;
use constant BMAX_COMMENT => 9000;
use constant CMAX_COMMENT => 4300;
use constant BMAX_MEMORY  => 150;
use constant CMAX_MEMORY  => 80;
use constant BMAX_NAME    => 100;
use constant CMAX_NAME    => 50;
use constant BMAX_KEYWORD => 80;
use constant CMAX_KEYWORD => 40;
use constant BMAX_PROP    => 255;   # logprop[2]/talkprop[2]/userproplite (not userprop)
use constant CMAX_PROP    => 100;
use constant BMAX_GRPNAME => 60;
use constant CMAX_GRPNAME => 30;
use constant BMAX_EVENT   => 65535;
use constant CMAX_EVENT   => 65535;
use constant BMAX_INTEREST => 100;
use constant CMAX_INTEREST => 50;

# declare views (calls into ljviews.pl)
@LJ::views = qw(lastn friends calendar day);
%LJ::viewinfo = (
                 "lastn" => {
                     "creator" => \&LJ::S1::create_view_lastn,
                     "des" => "Most Recent Events",
                 },
                 "calendar" => {
                     "creator" => \&LJ::S1::create_view_calendar,
                     "des" => "Calendar",
                 },
                 "day" => {
                     "creator" => \&LJ::S1::create_view_day,
                     "des" => "Day View",
                 },
                 "friends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends View",
                     "owner_props" => ["opt_usesharedpic", "friendspagetitle"],
                 },
                 "friendsfriends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends of Friends View",
                     "styleof" => "friends",
                 },
                 "rss" => {
                     "creator" => \&LJ::S1::create_view_rss,
                     "des" => "RSS View (XML)",
                     "nostyle" => 1,
                     "owner_props" => ["opt_whatemailshow", "no_mail_alias"],
                 },
                 "res" => {
                     "des" => "S2-specific resources (stylesheet)",
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
sub use_diff_db {
    $LJ::DBIRole->use_diff_db(@_);
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
sub get_dbh {
    if ($LJ::DEBUG{'get_dbh'} && $_[0] ne "logs") {
        my $errmsg = "get_dbh(@_) at \n";
        my $i = 0;
        while (my ($p, $f, $l) = caller($i++)) {
            next if $i > 3;
            $errmsg .= "  $p, $f, $l\n";
        }
        warn $errmsg;
    }
    $LJ::DBIRole->get_dbh(@_);
}

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
    my $sth;
    my $db = LJ::get_dbh("oldids") || LJ::get_db_reader();
    return $db->selectrow_arrayref("SELECT userid, newid FROM oldids ".
                                   "WHERE area=? AND oldid=?", undef,
                                   $_[0], $_[1]);
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

sub invalidate_friends_view_cache {
    my $u = shift;
    return unless $LJ::FV_CACHING;
    my $udbh = LJ::get_cluster_master($u);
    $udbh->do("DELETE FROM fvcache WHERE userid=?", undef, $u->{'userid'})
        if $udbh;
}

sub get_cached_friend_items
{
    my ($u, $packedref, $want, $maskfrom, $opts) = @_;
    
    my $packnum = int(length($$packedref) / 8);
    my $last = $want < $packnum ? $want : $packnum;

    my %to_load;  # clusterid -> [ [journalid, itemid]* ]
    my %anum;     # userid -> jitemid -> anum
    for (my $i=0; $i<$last; $i++) {
        # [3:userid][1:clusterid][3:jitemid][1:anum]
        my @a = unpack("NN", substr($$packedref, $i*8, 8));
        my $clusterid = $a[0] & 255;
        my $userid = $a[0] >> 8;
        my $anum = $a[1] & 255;
        my $jitemid = $a[1] >> 8;
        next unless $clusterid;  # cluster 0 not supported! (yet? no, probably never.)
        push @{$to_load{$clusterid}}, [ $userid, $jitemid ];
        $anum{$userid}->{$jitemid} = $anum;
    }

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($opts->{'dateformat'} eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    my @items;
    while (my ($c, $its) = each %to_load) {
        my $udbr = LJ::get_cluster_reader($c);
        my $sql = ("SELECT jitemid AS 'itemid', posterid, security, allowmask, replycount, journalid AS 'ownerid', rlogtime, ".
                   "DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum ".
                   "FROM log2 WHERE " . join(" OR ", map { "(journalid=$_->[0] AND jitemid=$_->[1])" } @$its));
        my $sth = $udbr->prepare($sql);
        $sth->execute;
        while (my $li = $sth->fetchrow_hashref) {
            next unless $anum{$li->{'ownerid'}}->{$li->{'itemid'}} == $li->{'anum'};
            next if $li->{'security'} eq "private" && $li->{'ownerid'} != $u->{'userid'};
            next if $li->{'security'} eq "usemask" && (($li->{'allowmask'}+0) & $maskfrom->{$li->{'ownerid'}}) == 0;
            $li->{'clusterid'} = $c;  # used/set elsewhere
            $li->{'_fromcache'} = 1;  # so we know what's non-cached later
            push @items, $li;
        }
    }

    return sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @items;    
}

sub set_cached_friend_items
{
    my ($u, $moddate, $itemref, $packedref) = @_;

    my $new; # new packed string
    my %seen; # what items we've added already
    my $len = 0;  # how many items have been added to string
    my $uncached = 0;  # how many items were from traditional fetch, not from previous cache
    foreach my $it (@$itemref) {
        $new .= pack("NN", ($it->{'ownerid'} << 8) + $it->{'clusterid'},
                     ($it->{'itemid'} << 8) + $it->{'anum'});
        
        my $itemid = ($it->{'itemid'} << 8) + $it->{'anum'};
        $seen{$it->{'ownerid'}}->{$itemid} = 1;
        $len++;
        $uncached++ unless $it->{'_fromcache'};
    }

    my $i = 0;
    my $packnum = int(length($$packedref) / 8);
    while ($i < $packnum && $len < $LJ::MAX_SCROLLBACK_FRIENDS) {
        my $sec = substr($$packedref, $i*8, 8);
        $i++;

        my @a = unpack("NN", $sec);
        my $userid = $a[0] >> 8;
        my $itemid = $a[1];
        next if $seen{$userid}->{$itemid};
        $new .= $sec;
    }

    if ($uncached > $LJ::FV_CACHE_WRITE_AFTER) {
        my $udbh = LJ::get_cluster_master($u);
        $udbh->do("REPLACE INTO fvcache (userid, maxupdate, items) VALUES (?,?,?)", undef,
                  $u->{'userid'}, $moddate, $new);
    }
}

sub get_groupmask
{
    my ($journal, $remote) = @_;
    return 0 unless $journal && $remote;
    my $jid = want_userid($journal);
    my $fid = want_userid($remote);
    return 0 unless $jid && $fid;
    my $memkey = [$jid,"frgmask:$jid:$fid"];
    my $mask = LJ::MemCache::get($memkey);
    unless (defined $mask) {
        my $dbr = LJ::get_db_reader();
        $mask = $dbr->selectrow_array("SELECT groupmask FROM friends ".
                                      "WHERE userid=? AND friendid=?",
                                      undef, $jid, $fid);
        LJ::MemCache::set($memkey, $mask+0, time()+60*15);
    }
    return $mask;
}

# <LJFUNC>
# name: LJ::get_friend_items
# des: Return friend items for a given user, filter, and period.
# args: dbarg?, opts
# des-opts: Hashref of options:
#           - userid
#           - remoteid
#           - itemshow
#           - skip
#           - filter  (opt) defaults to all
#           - owners  (opt) hashref to set found userid keys to value 1
#           - idsbycluster (opt) hashref to set clusterid key to [ [ journalid, itemid ]+ ]
#           - dateformat:  either "S2" for S2 code, or anything else for S1
#           - common_filter:  set true if this is the default view
#           - friendsoffriends: load friends of friends, not just friends
#           - u: hashref of journal loading friends of
#           - showtypes: /[PYC]/
# returns: Array of item hashrefs containing the same elements 
# </LJFUNC>
sub get_friend_items
{
    &nodb; 
    my $opts = shift;

    my $dbr = LJ::get_db_reader();
    my $sth;

    my $userid = $opts->{'userid'}+0;
    return () if $LJ::FORCE_EMPTY_FRIENDS{$userid};

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($dbr, $remoteid);
    }

    my @items = ();
    my $itemshow = $opts->{'itemshow'}+0;
    my $skip = $opts->{'skip'}+0;
    my $getitems = $itemshow + $skip;

    my $filter = $opts->{'filter'}+0;

    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14;  # 2 week default.
    my $lastmax = $LJ::EndOfTime - time() + $max_age;
    my $lastmax_cutoff = 0; # if nonzero, never search for entries with rlogtime higher than this (set when cache in use)

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
    }

    # common case: logged in user viewing their own friends page, without filtering
    my ($could_cache, $used_cache) = (0, 0);
    my $cache_changes;  # how many new items were added (later) to what we pulled from the cache
    my ($cache_max_update, $cache_new_update);
    my $fvcache;
    if ($LJ::FV_CACHING && $remote && $remote->{'userid'} == $userid && 
        ($LJ::FV_CACHING == 2 || LJ::get_cap($remote, "betatest")) && # <-- temporary
        $opts->{'common_filter'} && ! $opts->{'friendsoffriends'}) 
    {
        $could_cache = 1;  # so we save later, if enough new stuff
        my $udbr = LJ::get_cluster_reader($opts->{'u'});
        $fvcache = $udbr->selectrow_arrayref("SELECT maxupdate, items FROM fvcache ".
                                             "WHERE userid=?", undef, $userid);
        if ($fvcache) {
            my $cache_size = length($fvcache->[1]) / 8;
            if ($cache_size >= $getitems) {
                $cache_new_update = $cache_max_update = $fvcache->[0];
                $used_cache = 1;
                push @items, LJ::get_cached_friend_items($opts->{'u'}, \$fvcache->[1], $getitems, $gmask_from, {
                    'dateformat' => $opts->{'dateformat'}, 
                });
                $lastmax_cutoff = $lastmax = $items[0]->{'rlogtime'} - 1 if @items;
            }
        }
    }


    my $filtersql;
    if ($filter) {
        $filtersql = "AND f.groupmask & $filter";
    }

    my @friends_buffer = ();
    my $fr_loaded = 0;  # flag:  have we loaded friends?

    my $get_next_friend = sub
    {
        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;

        # load another batch if we just started or
        # if we just finished a batch.
        unless ($fr_loaded++) {
            my $extra;
            if ($opts->{'showtypes'}) {
                my @in;
                if ($opts->{'showtypes'} =~ /P/) { push @in, "'P'"; }
                if ($opts->{'showtypes'} =~ /Y/) { push @in, "'Y'"; }
                if ($opts->{'showtypes'} =~ /C/) { push @in, "'C','S','N'"; }
                $extra = "AND u.journaltype IN (".join (',', @in).")" if @in;
            }
            my $timeafter = $cache_max_update ? "AND uu.timeupdate > '$cache_max_update' " : "";
            my $sth = $dbr->prepare("SELECT u.userid, u.clusterid, uu.timeupdate ".
                                    "FROM friends f, userusage uu, user u ".
                                    "WHERE f.userid=? AND f.friendid=uu.userid ".
                                    "AND f.friendid=u.userid $filtersql AND u.statusvis='V' $extra ".
                                    "AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 14 DAY) " .
                                    $timeafter .
                                    "LIMIT 500");
            $sth->execute($userid);

            while (my ($userid, $clusterid, $timeupdate) = $sth->fetchrow_array) {
                my $update = $LJ::EndOfTime - LJ::mysqldate_to_time($timeupdate);
                push @friends_buffer, [ $userid, $update, $clusterid, $timeupdate ];
            }

            @friends_buffer = sort { $a->[1] <=> $b->[1] } @friends_buffer;

            # return one if we just found some fine, else we're all
            # out and there's nobody else to load.
            return $friends_buffer[0] if @friends_buffer;
            return undef;
        }

        # otherwise we must've run out.
        return undef;
    };

    # friends of friends mode
    $get_next_friend = sub
    {
        unless (@friends_buffer || $fr_loaded) 
        {
            # load all user's friends
            my %f;
            my $sth = $dbr->prepare(qq{
                SELECT f.friendid, f.groupmask, $LJ::EndOfTime-UNIX_TIMESTAMP(uu.timeupdate),
                u.journaltype FROM friends f, userusage uu, user u
                WHERE f.userid=$userid AND f.friendid=uu.userid AND u.userid=f.friendid
            });
            $sth->execute;
            while (my ($id, $mask, $time, $jt) = $sth->fetchrow_array) {
                $f{$id} = { 'userid' => $id, 'timeupdate' => $time, 'jt' => $jt,
                            'relevant' => ($filter && !($mask & $filter)) ? 0 : 1 , };
            }
            
            # load some friends of friends (most 20 queries)
            my %ff;
            my $fct = 0;
            foreach my $fid (sort { $f{$a}->{'timeupdate'} <=> $f{$b}->{'timeupdate'} } keys %f)
            {
                next unless $f{$fid}->{'jt'} eq "P" and $f{$fid}->{'relevant'};
                last if ++$fct > 20;
                my $extra;
                if ($opts->{'showtypes'}) {
                    my @in;
                    if ($opts->{'showtypes'} =~ /P/) { push @in, "'P'"; }
                    if ($opts->{'showtypes'} =~ /Y/) { push @in, "'Y'"; }
                    if ($opts->{'showtypes'} =~ /C/) { push @in, "'C','S','N'"; }
                    $extra = "AND u.journaltype IN (".join (',', @in).")" if @in;
                }
                my $sth = $dbr->prepare(qq{
                    SELECT u.userid, $LJ::EndOfTime-UNIX_TIMESTAMP(uu.timeupdate), u.clusterid 
                    FROM friends f, userusage uu, user u WHERE f.userid=$fid AND
                         f.friendid=uu.userid AND f.friendid=u.userid AND u.statusvis='V' $extra
                         AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 14 DAY) LIMIT 100
                });
                $sth->execute;
                while (my ($id, $time, $c) = $sth->fetchrow_array) {
                    next if $f{$id};  # we don't wanna see our friends
                    $ff{$id} = [ $id, $time, $c ];
                }
            }

            @friends_buffer = sort { $a->[1] <=> $b->[1] } values %ff;
            $fr_loaded = 1;
        }

        return $friends_buffer[0] if @friends_buffer;
        return undef;       
    } if $opts->{'friendsoffriends'};

    my $loop = 1;
    my $itemsleft = $getitems;  # even though we got a bunch, potentially, they could be old
    my $fr;

    while ($loop && ($fr = $get_next_friend->()))
    {
        shift @friends_buffer;

        # load the next recent updating friend's recent items
        my $friendid = $fr->[0];

        my @newitems = LJ::get_recent_items({
            'clustersource' => 'slave',
            'clusterid' => $fr->[2],
            'userid' => $friendid,
            'remote' => $remote,
            'itemshow' => $itemsleft,
            'skip' => 0,
            'gmask_from' => $gmask_from,
            'friendsview' => 1,
            'notafter' => $lastmax,
            'dateformat' => $opts->{'dateformat'},
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

            # update the time of the fv cache, if we're doing caching
            if ($could_cache && (! $cache_new_update || $fr->[3] gt $cache_new_update)) {
                $cache_new_update = $fr->[3];  # the DATETIME timeupdate field for the journal
            }

            $itemsleft--; # we'll need at least one less for the next friend

            # sort all the total items by rlogtime (recent at beginning)
            @items = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} } @items;

            # cut the list down to what we need.
            @items = splice(@items, 0, $getitems) if (@items > $getitems);
        }

        if (@items == $getitems)
        {
            $lastmax = $items[-1]->{'rlogtime'};
            $lastmax = $lastmax_cutoff if $lastmax_cutoff && $lastmax > $lastmax_cutoff;

            # stop looping if we know the next friend's newest entry
            # is greater (older) than the oldest one we've already
            # loaded.
            my $nextfr = $get_next_friend->();
            $loop = 0 if ($nextfr && $nextfr->[1] > $lastmax);
        }
    }

    # save the cache, if it changed.
    if ($could_cache && $cache_new_update ne $cache_max_update) {
        LJ::set_cached_friend_items($opts->{'u'}, $cache_new_update,
                                    \@items, \$fvcache->[1]);
    }

    # remove skipped ones
    splice(@items, 0, $skip) if $skip;

    # get items
    foreach (@items) {
        $opts->{'owners'}->{$_->{'ownerid'}} = 1;
    }

    # return the itemids grouped by clusters, if callers wants it.
    if (ref $opts->{'idsbycluster'} eq "HASH") {
        foreach (@items) {
            push @{$opts->{'idsbycluster'}->{$_->{'clusterid'}}},
            [ $_->{'ownerid'}, $_->{'itemid'} ];
        }
    }

    return @items;
}

# <LJFUNC>
# name: LJ::get_recent_items
# class:
# des: Returns journal entries for a given account.
# info:
# args: dbarg, opts
# des-opts: Hashref of options with keys:
#           -- err: scalar ref to return error code/msg in
#           -- userid
#           -- remote: remote user's $u
#           -- remoteid: id of remote user
#           -- clusterid: clusterid of userid
#           -- clustersource: if value 'slave', uses replicated databases
#           -- order: if 'logtime', sorts by logtime, not eventtime
#           -- friendsview: if true, sorts by logtime, not eventtime
#           -- notafter: upper bound inclusive for rlogtime/revttime (depending on sort mode),
#              defaults to no limit
#           -- skip: items to skip
#           -- itemshow: items to show
#           -- gmask_from: optional hashref of group masks { userid -> gmask } for remote
#           -- viewall: if set, no security is used.
#           -- dateformat: if "S2", uses S2's 'alldatepart' format.
#           -- itemids: optional arrayref onto which itemids should be pushed
# returns: array of hashrefs containing keys:
#          -- itemid (the jitemid)
#          -- posterid
#          -- security
#          -- replycount
#          -- alldatepart (in S1 or S2 fmt, depending on 'dateformat' req key)
#          -- ownerid (if in 'friendsview' mode)
#          -- rlogtime (if in 'friendsview' mode)
# </LJFUNC>
sub get_recent_items
{
    &nodb;
    my $opts = shift;

    my $dbr = LJ::get_db_reader();
    my $sth;

    my @items = ();             # what we'll return
    my $err = $opts->{'err'};

    my $userid = $opts->{'userid'}+0;

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($dbr, $remoteid);
    }

    my $max_hints = $LJ::MAX_HINTS_LASTN;  # temporary
    my $sort_key = "revttime";

    my $clusterid = $opts->{'clusterid'}+0;
    my @sources = ("cluster$clusterid");
    unshift @sources, ("cluster${clusterid}lite", "cluster${clusterid}slave")
        if $opts->{'clustersource'} eq "slave";
    my $logdb = LJ::get_dbh(@sources);

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
        if ($remote && $remote->{'journaltype'} eq "P" && $remoteid != $userid) {
            ## then we need to load the group mask for this friend
            $gmask_from->{$userid} = LJ::get_groupmask($userid, $remoteid);
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
        $extra_sql .= "journalid AS 'ownerid', rlogtime, ";
    }

    my $sql;

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($opts->{'dateformat'} eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    $sql = ("SELECT jitemid AS 'itemid', posterid, security, replycount, $extra_sql ".
            "DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum ".
            "FROM log2 USE INDEX ($sort_key) WHERE journalid=$userid AND $sort_key <= $notafter $secwhere ".
            "ORDER BY journalid, $sort_key ".
            "LIMIT $skip,$itemshow");

    unless ($logdb) {
        $$err = "nodb" if ref $err eq "SCALAR";
        return ();
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
# args: dbarg?, uuserid, propname, value, memonly?
# des-uuserid: The userid of the user or a user hashref.
# des-propname: The name of the property.  Or a hashref of propname keys and corresponding values.
# des-value: The value to set to the property.  If undefined or the
#            empty string, then property is deleted.
# des-memonly: if true, only writes to memcache, and not to database.
# </LJFUNC>
sub set_userprop
{
    &nodb;

    my ($u, $propname, $value, $memonly) = @_;
    $u = ref $u ? $u : LJ::load_userid($u);
    my $userid = $u->{'userid'}+0;

    my $hash = ref $propname eq "HASH" ? $propname : { $propname => $value };

    my %action;  # $table -> {"replace"|"delete"} -> [ "($userid, $propid, $qvalue)" | propid ]

    foreach $propname (keys %$hash) {
        my $p = LJ::get_prop("user", $propname) or next;
        my $table = $p->{'indexed'} ? "userprop" : "userproplite";
        if ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
            $table = "userproplite2";
        }
        unless ($memonly) {
            my $db = $action{$table}->{'db'} ||= ($table ne "userproplite2" ? LJ::get_db_writer() : 
                                                  LJ::get_cluster_master($u));
            return 0 unless $db;
        }
        $value = $hash->{$propname};
        if (defined $value && $value) {
            push @{$action{$table}->{"replace"}}, [ $p->{'id'}, $value ];
        } else {
            push @{$action{$table}->{"delete"}}, $p->{'id'};
        }
    }

    my $expire = time()+60*30;
    foreach my $table (keys %action) {
        my $db = $action{$table}->{'db'};
        if (my $list = $action{$table}->{"replace"}) {
            if ($db) {
                my $vals = join(',', map { "($userid,$_->[0]," . $db->quote($_->[1]) . ")" } @$list);
                $db->do("REPLACE INTO $table (userid, upropid, value) VALUES $vals");
            }
            foreach (@$list) {
                LJ::MemCache::set([$userid,"uprop:$userid:$_->[0]"], $_->[1], $expire) foreach (@$list);
            }
        }
        if (my $list = $action{$table}->{"delete"}) {
            if ($db) {
                my $in = join(',', @$list);
                $db->do("DELETE FROM $table WHERE userid=$userid AND upropid IN ($in)");
            }
            LJ::MemCache::set([$userid,"uprop:$userid:$_"], "", $expire) foreach (@$list);
        }
    }
    return 1;
}

# <LJFUNC>
# name: LJ::register_authaction
# des: Registers a secret to have the user validate.
# info: Some things, like requiring a user to validate their email address, require
#       making up a secret, mailing it to the user, then requiring them to give it
#       back (usually in a URL you make for them) to prove they got it.  This
#       function creates a secret, attaching what it's for and an optional argument.
#       Background maintenance jobs keep track of cleaning up old unvalidated secrets.
# args: dbarg?, userid, action, arg?
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
    &nodb;
    my $dbh = LJ::get_db_writer();

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
# args: dbarg?, userid, adminid, shtype, notes?
# des-userid: The user getting acted on.
# des-adminid: The site admin doing the action.
# des-shtype: The status history type code.
# des-notes: Optional notes associated with this action.
# </LJFUNC>
sub statushistory_add
{
    &nodb;
    my $dbh = LJ::get_db_writer();
    
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

    my $remote = LJ::get_remote();
    my $ret = "";
    if ((!$form->{'altlogin'} && $remote) || $opts->{'user'})
    {
        my $hpass;
        my $luser = $opts->{'user'} || $remote->{'user'};
        if ($opts->{'user'}) {
            $hpass = $form->{'hpassword'} || LJ::hash_password($form->{'password'});
        } elsif ($remote) {
            $ret .= "<input type='hidden' name='remoteuser' value='$remote->{'user'}' />\n";
            # this is merely to assist old code that only sends hpassword to auth_okay:
            $hpass = "_(remote)";
        }

        my $alturl = BML::self_link({ 'altlogin' => 1 });

        $ret .= "<tr align='left'><td colspan='2' align='left'>You are currently logged in as <b>$luser</b>.";
        $ret .= "<br />If this is not you, <a href='$alturl'>click here</a>.\n"
            unless $opts->{'noalt'};
        $ret .= "<input type='hidden' name='user' value='$luser' />\n";
        $ret .= "<input type='hidden' name='hpassword' value='$hpass' /><br />&nbsp;\n";
        $ret .= "</td></tr>\n";
    } else {
        $ret .= "<tr align='left'><td>Username:</td><td align='left'><input type='text' name='user' size='15' maxlength='15' value='";
        my $user = $form->{'user'};
        my $query_string = BML::get_query_string();
        unless ($user || $query_string =~ /=/) { $user=$query_string; }
        $ret .= BML::eall($user) unless ($form->{'altlogin'});
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
        my $query_string = BML::get_query_string();
        unless ($user || $query_string =~ /=/) { $user=$query_string; }
        $ret .= BML::eall($user) unless ($form->{'altlogin'});
        $ret .= "\" /></td></tr>\n";
        $ret .= "<tr><td align='right'><u>P</u>assword:</td><td align='left'>\n";
        $ret .= "<input type='password' name='password' size='15' maxlength='30' accesskey='p' value=\"" .
            LJ::ehtml($opts->{'password'}) . "\" />";
        $ret .= "</td></tr>\n";
        return $ret;
    }

    # logged in mode
    $ret .= "<tr><td align='right'><u>U</u>sername:</td><td align='left'>";

    my $alturl = BML::self_link({ 'altlogin' => 1 });
    my @shared = ($remote->{'user'});

    my $sopts = {};
    $sopts->{'notshared'} = 1 unless $opts->{'shared'};
    $sopts->{'notother'} = 1;

    $ret .= LJ::make_shared_select($dbs, $remote, $form, $sopts);

    if ($opts->{'getother'}) {
        my $alturl = BML::self_link({ 'altlogin' => 1 });
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
    unless ($opts->{'notother'}) {
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
# args: dbs?, u
# </LJFUNC>
sub get_shared_journals
{
    shift if ref $_[0] eq "LJ::DBSet";
    my $u = shift;
    my $ids = LJ::load_rel_target($u, 'A') || [];

    # have to get usernames;
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);
    return sort map { $_->{'user'} } values %users;
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
            my $ipbanned = 0;
            if (LJ::auth_okay($u, $f->{'password'}, $f->{'hpassword'}, $u->{'password'}, \$ipbanned)) {
                $$refu = $u;
                return $f->{'user'};
            } else {
                if ($ipbanned) {
                    $$referr = "Your IP address is temporarily banned for exceeding the login failure rate.";
                } else {
                    $$referr = "Invalid password.";
                }
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

    # check that they have admin access to this community
    my $authid = LJ::get_userid($dbs, $f->{'authas'});
    return $f->{'authas'}
    if ($authid && LJ::check_rel($dbs, $authid, $remote, 'A'));

    # else, complain.
    $$referr = "Invalid privileges to act as requested community.";
    return;
}

# <LJFUNC>
# name: LJ::get_authas_user
# des: Given a username, will return a user object if remote is an admin for the
#      username.  Otherwise returns undef
# returns: user object if authenticated, otherwise undef.
# args: user
# des-opts: Username of user to attempt to auth as.
# </LJFUNC>
sub get_authas_user {
    my $user = shift;
    return undef unless $user;

    # get a remote
    my $remote = LJ::get_remote();
    return undef unless $remote;

    # remote is already what they want?
    return $remote if $remote->{'user'} eq $user;

    # load user and authenticate
    my $u = LJ::load_user($user);
    return undef unless $u;

    # does $u have admin access?
    return undef unless LJ::can_manage($remote, $u);

    # passed all checks, return $u
    return $u;
}

# <LJFUNC>
# name: LJ::can_manage
# des: Given a user and a target user, will determine if the first user is an
#      admin for the target user.
# returns: bool: true if authorized, otherwise fail
# args: remote, u
# des-remote: user object or userid of user to try and authenticate
# des-u: user object or userid of target user
# </LJFUNC>
sub can_manage {
    my ($remote, $u) = @_;
    return undef unless $remote && $u;

    # is same user?
    return 1 if want_userid($remote) == want_userid($u);

    # check for admin access
    return undef unless LJ::check_rel($u, $remote, 'A');

    # passed checks, return true
    return 1;
}

sub can_delete_journal_item {
    return LJ::can_manage(@_);
}

# <LJFUNC>
# name: LJ::get_authas_list
# des: Get a list of usernames a given user can authenticate as
# returns: an array of usernames
# args: u, type?
# des-type: Optional.  'P' to only return users of journaltype 'P'
# </LJFUNC>
sub get_authas_list {
    my ($u, $type) = @_;

    # only one valid type right now
    $type = 'P' if $type;

    my $ids = LJ::load_rel_target($u, 'A');
    return undef unless $ids;

    # load_userids_multiple
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);

    return $u->{'user'}, sort map { $_->{'user'} }
                         grep { ! $type || $type eq $_->{'journaltype'} }
                         values %users;
}

# <LJFUNC>
# name: LJ::make_authas_select
# des: Given a u object and some options, determines which users the given user
#      can switch to.  If the list exists, returns a select list and a submit
#      button with labels.  Otherwise returns a hidden element.
# returns: string of html elements
# args: u, opts?
# des-opts: Optional.  Valid keys are:
#           'type' - the type argument to pass to LJ::get_authas_list
#           'authas' - current user, gets selected in drop-down
#           'label' - label to go before form elements
#           'button' - button label for submit button
# </LJFUNC>
sub make_authas_select {
    my ($u, $opts) = @_; # type, authas, label, button

    my @list = LJ::get_authas_list($u, $opts->{'type'});

    # only do most of form if there are options to select from
    if (@list > 1) {
        return ($opts->{'label'} || 'Work as user:') . " " . 
               LJ::html_select({ 'name' => 'authas',
                                 'selected' => $opts->{'authas'} || $u->{'user'}},
                                 map { $_, $_ } @list) . " " .
               LJ::html_submit(undef, $opts->{'button'} || 'Switch');
    }

    # no communities to choose from, give the caller a hidden
    return  LJ::html_hidden('authas', $opts->{'authas'} || $u->{'user'});
}

# <LJFUNC>
# name: LJ::is_valid_authaction
# des: Validates a shared secret (authid/authcode pair)
# info: See [func[LJ::register_authaction]].
# returns: Hashref of authaction row from database.
# args: dbarg?, aaid, auth
# des-aaid: Integer; the authaction ID.
# des-auth: String; the auth string. (random chars the client already got)
# </LJFUNC>
sub is_valid_authaction
{
    &nodb;

    # we use the master db to avoid races where authactions could be
    # used multiple times
    my $dbh = LJ::get_db_writer();
    my ($aaid, $auth) = @_;
    return $dbh->selectrow_hashref("SELECT aaid, userid, datecreate, authcode, action, arg1 ".
                                   "FROM authactions WHERE aaid=? AND authcode=?",
                                   undef, $aaid, $auth);
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
            $moodid = (defined $LJ::CACHE_MOODS{$moodid} ? 
                       $LJ::CACHE_MOODS{$moodid}->{'parent'} : 0);
        }
    }
    while ($moodid);
    return 0;
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

sub mysqldate_to_time {
    my $string = shift;
    return undef unless $string =~ /^(\d\d\d\d)-(\d\d)-(\d\d)(?: (\d\d):(\d\d)(?::(\d\d))?)?$/;
    return Time::Local::timelocal($6, $5, $4, $3, $2-1, $1);
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
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full userinfo.   Key 'type' when 'C' makes
#           a community link, not a user link.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser
{
    my $user = shift;
    my $opts = shift;
    my $andfull = $opts->{'full'} ? "&amp;mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    if ($opts->{'type'} eq "C") {
        return "<span class='ljuser' style='white-space:nowrap;'><a href='$LJ::SITEROOT/userinfo.bml?user=$user$andfull'><img src='$img/community.gif' alt='userinfo' width='16' height='16' style='vertical-align:bottom;border:0;' /></a><a href='$LJ::SITEROOT/community/$user/'><b>$user</b></a></span>";

    } else {
        return "<span class='ljuser' style='white-space:nowrap;'><a href='$LJ::SITEROOT/userinfo.bml?user=$user$andfull'><img src='$img/userinfo.gif' alt='userinfo' width='17' height='17' style='vertical-align:bottom;border:0;' /></a><a href='$LJ::SITEROOT/users/$user/'><b>$user</b></a></span>";
    }
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
# args: dbarg?, url, posterid, itemid, journalid?
# des-url: URL to log
# des-posterid: Userid of person posting
# des-itemid: Itemid URL appears in.  This is the display itemid,
#             which is the jitemid*256+anum from the [dbtable[log2]] table.
# des-journalid: Optional, journal id of item, if item is clustered.  Otherwise
#                this should be zero or undef.
# </LJFUNC>
sub record_meme
{
    &nodb;
    my ($url, $posterid, $itemid, $jid) = @_;

    $url =~ s!/$!!;  # strip / at end
    LJ::run_hooks("canonicalize_url", \$url);

    # canonicalize_url hook might just erase it, so
    # we don't want to record it.
    return unless $url;

    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE DELAYED INTO meme (url, posterid, journalid, itemid) " .
             "VALUES (?, ?, ?, ?)", undef, $url, $posterid, $jid, $itemid);
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
    return LJ::run_hook("name_caps", $caps);
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
    return LJ::run_hook("name_caps_short", $caps);
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
    return "$pre<?help $LJ::HELPURL{$topic} help?>$post";
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
    my ($hookname, @args) = @_;
    my @ret;
    foreach my $hook (@{$LJ::HOOKS{$hookname} || []}) {
        push @ret, [ $hook->(@args) ];
    }
    return @ret;
}

# <LJFUNC>
# name: LJ::run_hook
# des: Runs single site-specific hook of the given name.
# returns: return value from hook
# args: hookname, args*
# des-args: Arguments to be passed to hook.
# </LJFUNC>
sub run_hook
{
    my ($hookname, @args) = @_;
    return undef unless @{$LJ::HOOKS{$hookname} || []};
    return $LJ::HOOKS{$hookname}->[0]->(@args);
    return undef;
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
# name: LJ::register_setter
# des: Installs code to run for the "set" command in the console.
# info: Setters can be general or site-specific.
# args: key, subref
# des-key: Key to set.
# des-subref: Subroutine reference to run later.
# </LJFUNC>
sub register_setter
{
    my $key = shift;
    my $subref = shift;
    $LJ::SETTER{$key} = $subref;
}

register_setter("newpost_minsecurity", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    my $dbs = LJ::make_dbs_from_arg($dba);
    unless ($value =~ /^(public|friends|private)$/) {
        $$err = "Illegal value.  Must be 'public', 'friends', or 'private'";
        return 0;
    }
    # Don't let commmunities be private
    if ($u->{'journaltype'} eq "C" && $value eq "private") {
        $$err = "newpost_minsecurity cannot be private for communities";
        return 0;
    }
    $value = "" if $value eq "public";
    LJ::set_userprop($u, "newpost_minsecurity", $value);
    return 1;
});

register_setter("stylesys", sub {
    my ($dba, $u, $remote, $key, $value, $err) = @_;
    my $dbs = LJ::make_dbs_from_arg($dba);
    unless ($value =~ /^[sS]?(1|2)$/) {
        $$err = "Illegal value.  Must be S1 or S2.";
        return 0;
    }
    $value = $1 + 0;
    LJ::set_userprop($u, "stylesys", $value);
    return 1;
});


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
# des: Creates invitation code(s) from an optional userid
#      for use by anybody.
# returns: Code generated (if quantity 1),
#          number of codes generated (if quantity>1),
#          or undef on failure.
# args: dbarg?, userid?, quantity?
# des-userid: Userid to make the invitation code from,
#             else the code will be from userid 0 (system)
# des-quantity: Number of codes to generate (default 1)
# </LJFUNC>
sub acct_code_generate
{
    &nodb;
    my $userid = int(shift);
    my $quantity = shift || 1;

    my $dbh = LJ::get_db_writer();

    my @authcodes = map {LJ::make_auth_code(5)} 1..$quantity;
    my @values = map {"(NULL, $userid, 0, '$_')"} @authcodes;
    my $sql = "INSERT INTO acctcode (acid, userid, rcptid, auth) "
            . "VALUES " . join(",", @values);
    my $num_rows = $dbh->do($sql) or return undef;

    if ($quantity == 1) {
	my $acid = $dbh->{'mysql_insertid'} or return undef;
	return acct_code_encode($acid, $authcodes[0]);
    } else {
        return $num_rows;
    }
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
# args: dbarg?, code, err?, userid?
# des-code: account code to check
# des-err: optional scalar ref to put error message into on failure
# des-userid: optional userid which is allowed in the rcptid field,
#             to allow for htdocs/create.bml case when people double
#             click the submit button.
# </LJFUNC>
sub acct_code_check
{
    &nodb;
    my $code = shift;
    my $err = shift;     # optional; scalar ref
    my $userid = shift;  # optional; acceptable userid (double-click proof)

    my $dbh = LJ::get_db_writer();

    unless (length($code) == 12) {
        $$err = "Malformed code; not 12 characters.";
        return 0;
    }

    my ($acid, $auth) = acct_code_decode($code);

    my $ac = $dbh->selectrow_hashref("SELECT userid, rcptid, auth ".
                                     "FROM acctcode WHERE acid=?", 
                                     undef, $acid);

    unless ($ac && $ac->{'auth'} eq $auth) {
        $$err = "Invalid account code.";
        return 0;
    }

    if ($ac->{'rcptid'} && $ac->{'rcptid'} != $userid) {
        $$err = "This code has already been used.";
        return 0;
    }

    # is the journal this code came from suspended?
    my $u = LJ::load_userid($ac->{'userid'});
    if ($u && $u->{'statusvis'} eq "S") {
        $$err = "Code belongs to a suspended account.";
        return 0;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::load_mood_theme
# des: Loads and caches a mood theme, or returns immediately if already loaded.
# args: dbarg?, themeid
# des-themeid: the mood theme ID to load
# </LJFUNC>
sub load_mood_theme
{
    &nodb;
    my $themeid = shift;
    return if $LJ::CACHE_MOOD_THEME{$themeid};
    return unless $themeid;
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT moodid, picurl, width, height FROM moodthemedata WHERE moodthemeid=?");
    $sth->execute($themeid);
    while (my ($id, $pic, $w, $h) = $sth->fetchrow_array) {
        $LJ::CACHE_MOOD_THEME{$themeid}->{$id} = { 'pic' => $pic, 'w' => $w, 'h' => $h };
    }
}

# <LJFUNC>
# name: LJ::load_props
# des: Loads and caches one or more of the various *proplist tables:
#      logproplist, talkproplist, and userproplist, which describe
#      the various meta-data that can be stored on log (journal) items,
#      comments, and users, respectively.
# args: dbarg?, table*
# des-table: a list of tables' proplists to load.  can be one of
#            "log", "talk", "user", or "rate"
# </LJFUNC>
sub load_props
{
    my $dbarg = ref $_[0] ? shift : undef;
    my @tables = @_;
    my $dbr;
    my %keyname = qw(log  propid
                     talk tpropid
                     user upropid
                     rate rlid
                     );

    foreach my $t (@tables) {
        next unless defined $keyname{$t};
        next if defined $LJ::CACHE_PROP{$t};
        my $tablename = $t eq "rate" ? "ratelist" : "${t}proplist";
        $dbr ||= LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT * FROM $tablename");
        $sth->execute;
        while (my $p = $sth->fetchrow_hashref) {
            $p->{'id'} = $p->{$keyname{$t}};
            $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
            $LJ::CACHE_PROPID{$t}->{$p->{'id'}} = $p;
        }
    }
}

# <LJFUNC>
# name: LJ::get_prop
# des: This is used to retrieve
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
    unless (defined $LJ::CACHE_PROP{$table}) {
        LJ::load_props($table);
        return undef unless $LJ::CACHE_PROP{$table};
    }
    return $LJ::CACHE_PROP{$table}->{$name};
}

# <LJFUNC>
# name: LJ::load_codes
# des: Populates hashrefs with lookup data from the database or from memory,
#      if already loaded in the past.  Examples of such lookup data include
#      state codes, country codes, color name/value mappings, etc.
# args: dbarg?, whatwhere
# des-whatwhere: a hashref with keys being the code types you want to load
#                and their associated values being hashrefs to where you
#                want that data to be populated.
# </LJFUNC>
sub load_codes
{
    &nodb;    
    my $req = shift;

    my $dbr = LJ::get_db_reader();

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
            "height=\"$i->{'height'}\" alt=\"$i->{'alt'}\" border='0'$attrs />";
    }
    if ($type eq "input") {
        return "<input type=\"image\" src=\"$LJ::IMGPREFIX$i->{'src'}\" ".
            "width=\"$i->{'width'}\" height=\"$i->{'height'}\" ".
            "alt=\"$i->{'alt'}\" border='0'$attrs />";
    }
    return "<b>XXX</b>";
}

# <LJFUNC>
# name: LJ::load_user_props
# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: dbarg?, u, opts?, propname*
# des-opts: hashref of opts.  set key 'cache' to use memcache.
# des-propname: the name of a property from the userproplist table.
# </LJFUNC>
sub load_user_props
{
    &nodb;

    my $u = shift;
    return unless ref $u eq "HASH";

    my $opts = ref $_[0] ? shift : {};
    my (@props) = @_;

    my ($sql, $sth);
    LJ::load_props("user");

    ## user reference
    my $uid = $u->{'userid'}+0;
    $uid = LJ::get_userid($u->{'user'}) unless $uid;
    
    my $mem = {};
    if ($opts->{'cache'}) {
        my @keys;
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            next unless $p;
            push @keys, [$uid,"uprop:$uid:$p->{'id'}"];
        }
        $mem = LJ::MemCache::get_multi(@keys) || {};
    }
    my @needwrite;  # [propid, propname] entries we need to save to memcache later

    my %loadfrom;
    unless (@props) {
        # case 1: load all props for a given user.
        $loadfrom{'userprop'} = 1;
        $loadfrom{'userproplite'} = 1;
        $loadfrom{'userproplite2'} = 1;
    } else {
        # case 2: load only certain things
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            next unless $p;
            if (defined $mem->{"uprop:$uid:$p->{'id'}"}) {
                $u->{$_} = $mem->{"uprop:$uid:$p->{'id'}"};
                next;
            }
            push @needwrite, [ $p->{'id'}, $_ ];
            my $source = $p->{'indexed'} ? "userprop" : "userproplite";
            if ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
                $source = "userproplite2";  # clustered
            }
            push @{$loadfrom{$source}}, $p->{'id'};
        }
    }

    foreach my $table (keys %loadfrom) {
        my $db;
        if ($opts->{'cache'} && @LJ::MEMCACHE_SERVERS) {
            $db = $table eq "userproplite2" ? 
                LJ::get_cluster_master($u) : 
                LJ::get_db_writer();
        } else {
            $db = $table eq "userproplite2" ? 
                LJ::get_cluster_reader($u) : 
                LJ::get_db_reader();
        }
        $sql = "SELECT upropid, value FROM $table WHERE userid=$uid";
        if (ref $loadfrom{$table}) {
            $sql .= " AND upropid IN (" . join(",", @{$loadfrom{$table}}) . ")";
        }
        $sth = $db->prepare($sql);
        $sth->execute;
        while (my ($id, $v) = $sth->fetchrow_array) {
            $u->{$LJ::CACHE_PROPID{'user'}->{$id}->{'name'}} = $v;
        }
    }

    # Add defaults to user object.

    # defaults for S1 style IDs in config file are magic: really 
    # uniq strings representing style IDs, so on first use, we need
    # to map them
    unless ($LJ::CACHED_S1IDMAP) {
	foreach my $v (qw(lastn friends calendar day)) {
            my $k = "s1_${v}_style";
            next unless $LJ::USERPROP_DEF{$k} =~ m!^$v/(.+)$!;
            my $dbr = LJ::get_db_reader();
            my $id = $dbr->selectrow_array("SELECT styleid FROM style WHERE ".
                                           "user='system' AND type='$v' AND styledes=".
                                           $dbr->quote($1));
            $LJ::USERPROP_DEF{$k} = $id+0;
	}
	$LJ::CACHED_S1IDMAP = 1;
    }

    # If this was called with no @props, then the function tried
    # to load all metadata.  but we don't know what's missing, so
    # try to apply all defaults.
    unless (@props) { @props = keys %LJ::USERPROP_DEF; }

    foreach my $prop (@props) {
        next if (defined $u->{$prop});
        $u->{$prop} = $LJ::USERPROP_DEF{$prop};
    }

    if ($opts->{'cache'}) {
        my $expire = time() + 60*30;
        foreach my $wr (@needwrite) {
            my ($id, $name) = ($wr->[0], $wr->[1]);
            LJ::MemCache::set([$uid,"uprop:$uid:$id"], $u->{$name} || "", $expire);
        }
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
    $ret .= "<?badcontent?>\n<ul>\n";
    foreach (@errors) {
        $ret .= "<li>$_</li>\n";
    }
    $ret .= "</ul>\n";
    return $ret;
}

# <LJFUNC>
# name: LJ::debug
# des: When $LJ::DEBUG is set, logs the given message to
#      the Apache error log.  Or, if $LJ::DEBUG is 2, then
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
    my $r = Apache->request;
    return 0 unless $r;
    $r->log_error($_[0]);
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
# args: user_u, clear, md5, actual?, ip_banned?
# des-user_u: Either the user name or a user object.
# des-clear: Clear text password the client is sending. (need this or md5)
# des-md5: MD5 of the password the client is sending. (need this or clear).
#          If this value instead of clear, clear can be anything, as md5
#          validation will take precedence.
# des-actual: The actual password for the user.  Ignored if a pluggable
#             authenticator is being used.  Required unless the first
#             argument is a user object instead of a username scalar.
# des-ip_banned: Optional scalar ref which this function will set to true
#                if IP address of remote user is banned.
# </LJFUNC>
sub auth_okay
{
    my $user = shift;
    my $clear = shift;
    my $md5 = shift;
    my $actual = shift;
    my $ip_banned = shift;

    my $u;

    # first argument can be a user object instead of a string, in
    # which case the actual password (last argument) is got from the
    # user object.
    if (ref $user eq "HASH") {
        $u = $user;
        $actual = $user->{'password'};
        $user = $user->{'user'};
    } else {
        $u = LJ::load_user($u);
    }
    
    # this magic hpassword value is set by auth_fields() to make 
    # moving the old to the new login system faster.  it should
    # be killed in phase 2, though, where we remove hpassword
    # entirely.
    if ($md5 eq "_(remote)") {
        my $remote = LJ::get_remote();
        return 1 if 
            $remote && $remote->{'userid'} == $u->{'userid'};
    }

    # set the IP banned flag, if it was provided.
    my $fake_scalar;
    my $ref = ref $ip_banned ? $ip_banned : \$fake_scalar;
    if (LJ::login_ip_banned($u)) {
        $$ref = 1;
        return 0;
    } else {
        $$ref = 0;
    }

    my $bad_login = sub {
        LJ::handle_bad_login($u);
        return 0;
    };

    ## custom authorization:
    if (ref $LJ::AUTH_CHECK eq "CODE") {
        my $type = $md5 ? "md5" : "clear";
        my $try = $md5 || $clear;
        my $good = $LJ::AUTH_CHECK->($user, $try, $type);
        return $good || $bad_login->();
    }

    ## LJ default authorization:   
    return $bad_login->() unless $actual;
    return 1 if ($md5 && lc($md5) eq LJ::hash_password($actual));
    return 1 if ($clear eq $actual);
    return $bad_login->();
}

# <LJFUNC>
# name: LJ::create_account
# des: Creates a new basic account.  <b>Note:</b> This function is
#      not really too useful but should be extended to be useful so
#      htdocs/create.bml can use it, rather than doing the work itself.
# returns: integer of userid created, or 0 on failure.
# args: dbarg?, opts
# des-opts: hashref containing keys 'user', 'name', and 'password'
# </LJFUNC>
sub create_account
{
    &nodb;    
    my $o = shift;

    my $user = LJ::canonical_username($o->{'user'});
    unless ($user)  {
        return 0;
    }

    my $dbh = LJ::get_db_writer();
    my $quser = $dbh->quote($user);
    my $cluster = defined $o->{'cluster'} ? $o->{'cluster'} : LJ::new_account_cluster();
    my $caps = $o->{'caps'} || $LJ::NEWUSER_CAPS;

    # new non-clustered accounts aren't supported anymore
    return 0 unless $cluster;

    $dbh->do("INSERT INTO user (user, name, password, clusterid, dversion, caps) ".
             "VALUES ($quser, ?, ?, ?, $LJ::MAX_DVERSION, ?)", undef,
             $o->{'name'}, $o->{'password'}, $cluster, $caps);
    return 0 if $dbh->err;
    
    my $userid = $dbh->{'mysql_insertid'};
    return 0 unless $userid;

    $dbh->do("INSERT INTO useridmap (userid, user) VALUES ($userid, $quser)");
    $dbh->do("INSERT INTO userusage (userid, timecreate) VALUES ($userid, NOW())");

    LJ::run_hooks("post_create", {
        'userid' => $userid,
        'user' => $user,
        'code' => undef,
    });
    return $userid;
}

# <LJFUNC>
# name: LJ::new_account_cluster
# des: Which cluster to put a new account on.  $DEFAULT_CLUSTER if it's
#      a scalar, random element from @$DEFAULT_CLUSTER if it's arrayref.
# returns: clusterid where the new account should be created
# </LJFUNC>
sub new_account_cluster
{
    return (ref $LJ::DEFAULT_CLUSTER
            ? $LJ::DEFAULT_CLUSTER->[int rand scalar @$LJ::DEFAULT_CLUSTER]
            : $LJ::DEFAULT_CLUSTER+0);
}

# <LJFUNC>
# name: LJ::is_friend
# des: Checks to see if a user is a friend of another user.
# returns: boolean; 1 if user B is a friend of user A or if A == B
# args: usera, userb
# des-usera: Source user hashref or userid.
# des-userb: Destination user hashref or userid. (can be undef)
# </LJFUNC>
sub is_friend
{
    &nodb;
    my $ua = shift;
    my $ub = shift;

    my $uaid = (ref $ua ? $ua->{'userid'} : $ua)+0;
    my $ubid = (ref $ub ? $ub->{'userid'} : $ub)+0;

    return 0 unless $uaid;
    return 0 unless $ubid;
    return 1 if ($uaid == $ubid);

    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array("SELECT COUNT(*) FROM friends WHERE ".
                                 "userid=$uaid AND friendid=$ubid");
}

# <LJFUNC>
# name: LJ::is_banned
# des: Checks to see if a user is banned from a journal.
# returns: boolean; 1 iff user B is banned from journal A
# args: user, journal
# des-user: User hashref or userid.
# des-journal: Journal hashref or userid.
# </LJFUNC>
sub is_banned
{
    &nodb;
    my $u = shift;
    my $j = shift;

    my $uid = (ref $u ? $u->{'userid'} : $u)+0;
    my $jid = (ref $j ? $j->{'userid'} : $j)+0;

    return 1 unless $uid;
    return 1 unless $jid;

    # for speed: common case is non-community posting and replies
    # in own journal.  avoid db hit.
    return 0 if ($uid == $jid);

    return LJ::check_rel($jid, $uid, 'B');
}

# <LJFUNC>
# name: LJ::can_view
# des: Checks to see if the remote user can view a given journal entry.
#      <b>Note:</b> This is meant for use on single entries at a time,
#      not for calling many times on every entry in a journal.
# returns: boolean; 1 if remote user can see item
# args: remote, item
# des-item: Hashref from the 'log' table.
# </LJFUNC>
sub can_view
{
    &nodb;
    my $remote = shift;
    my $item = shift;

    # public is okay
    return 1 if ($item->{'security'} eq "public");

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid = int($item->{'ownerid'} || $item->{'journalid'});
    my $remoteid = int($remote->{'userid'});

    # owners can always see their own.
    return 1 if ($userid == $remoteid);

    # other people can't read private
    return 0 if ($item->{'security'} eq "private");

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless ($item->{'security'} eq "usemask");

    # usemask
    my $dbr = LJ::get_db_reader();

    # if it's usemask, we have to refuse non-personal journals,
    # so we have to load the user
    return 0 unless $remote->{'journaltype'} eq 'P';

    my $gmask = $dbr->selectrow_array("SELECT groupmask FROM friends WHERE ".
                                      "userid=$userid AND friendid=$remoteid");
    my $allowed = (int($gmask) & int($item->{'allowmask'}));
    return $allowed ? 1 : 0;  # no need to return matching mask
}

# <LJFUNC>
# name: LJ::get_logtext2
# des: Efficiently retrieves a large number of journal entry text, trying first
#      slave database servers for recent items, then the master in
#      cases of old items the slaves have already disposed of.  See also:
#      [func[LJ::get_talktext2]].
# args: u, opts?, jitemid*
# returns: hashref with keys being jitemids, values being [ $subject, $body ]
# des-opts: Optional hashref of special options.  Currently only 'usemaster'
#           key is supported, which always returns a definitive copy,
#           and not from a cache or slave database.
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

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach my $id (@_) { 
        $id += 0;
        $need{$id} = 1;
        push @mem_keys, [$journalid,"logtext:$clusterid:$journalid:$id"];
    }

    # pass 0: memory, avoiding databases
    unless ($opts->{'usemaster'}) {
        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
        while (my ($k, $v) = each %$mem) {
            next unless $v;
            $k =~ /:(\d+):(\d+):(\d+)/;
            delete $need{$3};
            $lt->{$3} = $v;
        }
    }

    return $lt unless %need;

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass (1, 2) {
        next unless %need;
        next if $pass == 1 && $opts->{'usemaster'};
        my $db = $pass == 1 ? LJ::get_cluster_reader($clusterid) :
            LJ::get_cluster_master($clusterid);
        next unless $db;
        
        my $jitemid_in = join(", ", keys %need);
        my $sth = $db->prepare("SELECT jitemid, subject, event FROM logtext2 ".
                               "WHERE journalid=$journalid AND jitemid IN ($jitemid_in)");
        $sth->execute;
        while (my ($id, $subject, $event) = $sth->fetchrow_array) {
            my $val = [ $subject, $event ];
            $lt->{$id} = $val;
            LJ::MemCache::add([$journalid,"logtext:$clusterid:$journalid:$id"], $val);
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
# des-opts: A hashref of options. 'onlysubjects' will only retrieve subjects.
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

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach my $id (@_) {
        $id += 0;
        $need{$id} = 1;
        push @mem_keys, [$journalid,"talksubject:$clusterid:$journalid:$id"];
        unless ($opts->{'onlysubjects'}) {
            push @mem_keys, [$journalid,"talkbody:$clusterid:$journalid:$id"];
        }
    }

    # try the memory cache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $v;
        $k =~ /^talk(.*):(\d+):(\d+):(\d+)/;
        if ($opts->{'onlysubjects'} && $1 eq "subject") {
            delete $need{$4};
            $lt->{$4} = [ $v ];
        }
        if (! $opts->{'onlysubjects'} && $1 eq "body" &&
            exists $mem->{"talksubject:$2:$3:$4"}) {
            delete $need{$4};
            $lt->{$4} = [ $mem->{"talksubject:$2:$3:$4"}, $v ];
        }
    }
    return $lt unless %need;
    
    my $bodycol = $opts->{'onlysubjects'} ? "" : ", body";

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass (1, 2) {
        next unless %need;
        my $db = $pass == 1 ? LJ::get_cluster_reader($clusterid) :
            LJ::get_cluster_master($clusterid);
        next unless $db;
        my $in = join(",", keys %need);
        my $sth = $db->prepare("SELECT jtalkid, subject $bodycol FROM talktext2 ".
                               "WHERE journalid=$journalid AND jtalkid IN ($in)");
        $sth->execute;
        while (my ($id, $subject, $body) = $sth->fetchrow_array) {
            $lt->{$id} = [ $subject, $body ];
            LJ::MemCache::add([$journalid,"talkbody:$clusterid:$journalid:$id"], $body)
                unless $opts->{'onlysubjects'};
            LJ::MemCache::add([$journalid,"talksubject:$clusterid:$journalid:$id"], $subject);
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
    &nodb;
    my $idsbyc = shift;
    my $sth;

    # return structure.
    my $lt = {};

    # keep track of itemids we still need to load per cluster
    my %need;
    my @mem_keys;
    foreach my $c (keys %$idsbyc) {
        foreach (@{$idsbyc->{$c}}) {
            if ($c) {
                $need{$c}->{"$_->[0] $_->[1]"} = 1;
                push @mem_keys, [$_->[0],"logtext:$c:$_->[0]:$_->[1]"];
            }
        }
    }

    # pass 0: memory, avoiding databases
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $v;
        $k =~ /:(\d+):(\d+):(\d+)/;
        delete $need{$1}->{"$2 $3"};
        $lt->{"$2 $3"} = $v;
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
                my $val = [ $subject, $event ];
                $lt->{"$jid $jitemid"} = $val;
                LJ::MemCache::add([$jid,"logtext:$c:$jid:$jitemid"], $val);
            }
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::get_remote
# des: authenticates the user at the remote end based on their cookies
#      and returns a hashref representing them
# returns: hashref containing 'user' and 'userid' if valid user, else
#          undef.
# args: dbarg?, criterr?, cgi?
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

    return $LJ::CACHE_REMOTE if $LJ::CACHED_REMOTE;

    $$criterr = 0;

    my $cookie = sub {
        return $cgi ? $cgi->cookie($_[0]) : $BML::COOKIE{$_[0]};
    };

    my $sopts;
    my $validate = sub {
        my $a = shift;
        # let hooks reject credentials, or set criterr true:
        my $hookparam = {
            'user' => $a->{'user'},
            'userid' => $a->{'userid'},
            'caps' => $a->{'caps'},
            'criterr' => $criterr,
            'cookiesource' => $cookie,
            'sopts' => $sopts,
        };
        my @r = LJ::run_hooks("validate_get_remote", $hookparam);
        return undef if grep { ! $_->[0] } @r;
        return 1;
    };

    my $no_remote = sub {
        $LJ::CACHED_REMOTE = 1;
        $LJ::CACHE_REMOTE = undef;
        $validate->();
        return undef;
    };

    my $sessdata;

    # do they have any sort of session cookie?
    return $no_remote->("No session") 
        unless ($sessdata = $cookie->('ljsession'));

    
    my ($authtype, $user, $sessid, $auth, $_sopts) = split(/:/, $sessdata);
    $sopts = $_sopts;

    # fail unless authtype is 'ws' (more might be added in future)
    return $no_remote->("No ws auth") unless $authtype eq "ws";

    my $u = LJ::load_user($user);
    return $no_remote->("User doesn't exist") unless $u;

    my $sess_db;
    my $sess;
    my $get_sess = sub {
        $sess = $sess_db->selectrow_hashref("SELECT * FROM sessions ".
                                            "WHERE userid=? AND sessid=? AND auth=?",
                                            undef, $u->{'userid'}, $sessid, $auth);
    };
    my $memkey = [$u->{'userid'},"sess:$u->{'userid'}:$sessid"];
    # try memory
    $sess = LJ::MemCache::get($memkey);
    # try master
    unless ($sess) {
        $sess_db = LJ::get_cluster_master($u);
        $get_sess->();
        LJ::MemCache::set($memkey, $sess) if $sess;
    }
    return $no_remote->("Session bogus") unless $sess;
    return $no_remote->("Invalid auth") unless $sess->{'auth'} eq $auth;
    my $now = time();
    return $no_remote->("Session old") if $sess->{'timeexpire'} < $now;
    if ($sess->{'ipfixed'}) {
        my $remote_ip = $LJ::_XFER_REMOTE_IP || LJ::get_remote_ip();
        return $no_remote->("Session wrong IP") 
            if $sess->{'ipfixed'} ne $remote_ip;
    }

    # renew short session
    my $sess_length = {
        'short' => 60*60*24*1.5,
        'long' => 60*60*24*60,
    }->{$sess->{'exptype'}};
    
    if ($sess_length && 
        $sess->{'timeexpire'} - $now < $sess_length/2) {
        my $udbh = LJ::get_cluster_master($u);
        if ($udbh) {
            my $future = $now + $sess_length;
            $udbh->do("UPDATE sessions SET timeexpire=$future WHERE ".
                      "userid=$u->{'userid'} AND sessid=$sess->{'sessid'}");
            my $dbh = LJ::get_db_writer();
            $dbh->do("UPDATE userusage SET timecheck=NOW() WHERE userid=?",
                     undef, $u->{'userid'});
            LJ::MemCache::delete($memkey);
        }
    }

    # augment hash with session data;
    $u->{'_session'} = $sess;

    $LJ::CACHED_REMOTE = 1;
    $LJ::CACHE_REMOTE = $u;

    eval {
        Apache->request->notes("ljuser" => $u->{'user'});
    };

    return $u;
}

sub set_remote
{
    my $remote = shift;
    $LJ::CACHED_REMOTE = 1;
    $LJ::CACHE_REMOTE = $remote;
    1;
}

sub load_remote
{
    # function is no longer used, since get_remote returns full objects.
    # keeping this here so we don't break people's local site code
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
    my $sess = $BML::COOKIE{'ljsession'};
    return { 'user' => $1 } if $sess =~ /^ws:(\w+):/;
    return undef;
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
    return (BML::get_method() eq "POST");
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
    return 1 unless $LJ::CLEAR_CACHES;
    $LJ::CLEAR_CACHES = 0;

    do "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
    do "$ENV{'LJHOME'}/cgi-bin/ljdefaults.pl";

    $LJ::DBIRole->flush_cache();

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

    # clear per-request caches
    %LJ::REQ_CACHE_USER_NAME = ();  # users by name
    %LJ::REQ_CACHE_USER_ID = ();    # users by id
    $LJ::CACHE_REMOTE = undef;
    $LJ::CACHED_REMOTE = 0;
    %LJ::REQ_CACHE_REL = ();  # relations from LJ::check_rel()
    %LJ::REQ_CACHE_DBS = ();  # clusterid -> LJ::DBSet
    %LJ::CACHE_USERPIC_SIZE = ();

    # we use this to fake out get_remote's perception of what
    # the client's remote IP is, when we transfer cookies between
    # authentication domains.  see the FotoBilder interface.
    $LJ::_XFER_REMOTE_IP = undef;

    # clear the handle request cache (like normal cache, but verified already for
    # this request to be ->ping'able).
    $LJ::DBIRole->clear_req_cache();

    # need to suck db weights down on every request (we check
    # the serial number of last db weight change on every request
    # to validate master db connection, instead of selecting
    # the connection ID... just as fast, but with a point!)
    $LJ::DBIRole->trigger_weight_reload();

    # reset BML's cookies
    eval { BML::reset_cookies() };

    # check the modtime of ljconfig.pl and reload if necessary
    # only do a stat every 10 seconds and then only reload
    # if the file has changed
    my $now = time();
    if ($now - $LJ::CACHE_CONFIG_MODTIME_LASTCHECK > 10) {
        my $modtime = (stat("$ENV{'LJHOME'}/cgi-bin/ljconfig.pl"))[9];
        if ($modtime > $LJ::CACHE_CONFIG_MODTIME) {
            # reload config and update cached modtime
            $LJ::CACHE_CONFIG_MODTIME = $modtime;
            eval { 
                do "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl"; 
                do "$ENV{'LJHOME'}/cgi-bin/ljdefaults.pl"; 
            };
            $LJ::DBIRole->set_sources(\%LJ::DBINFO);
            LJ::MemCache::trigger_bucket_reconstruct();
            if ($modtime > $now - 60) {
                # show to stderr current reloads.  won't show
                # reloads happening from new apache children
                # forking off the parent who got the inital config loaded
                # hours/days ago and then the "updated" config which is
                # a different hours/days ago.
                print STDERR "ljconfig.pl reloaded\n";
            }
        }
        $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = $now;
    }

    return 1;
}

sub end_request
{
    $LJ::DBIRole->disconnect_all() if $LJ::DISCONNECT_DBS;
    LJ::MemCache::disconnect_all() if $LJ::DISCONNECT_MEMCACHE;
}

# <LJFUNC>
# name: LJ::sysban_check
# des: Given a 'what' and 'value', checks to see if a ban exists
# args: what, value
# des-what: The ban type
# des-value: The value which triggers the ban
# returns: 1 if a ban exists, 0 otherwise
# </LJFUNC>
sub sysban_check {
    my ($what, $value) = @_;

    # cache if ip ban
    if ($what eq 'ip') {
        return $LJ::IP_BANNED{$value} if $LJ::IP_BANNED_LOADED;

        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;

        # set this now before the query
        $LJ::IP_BANNED_LOADED++;

        # build cache
        my $sth = $dbh->prepare("SELECT value FROM sysban " .
                                "WHERE status='active' AND what='ip' " .
                                "AND NOW() > bandate " .
                                "AND (NOW() < banuntil OR banuntil IS NULL)");
        $sth->execute();
        return undef $LJ::IP_BANNED_LOADED if $sth->err;
        $LJ::IP_BANNED{$_}++ while $_ = $sth->fetchrow_array;

        # return value to user
        return $LJ::IP_BANNED{$value};
    }

    # non-ip bans come straight from the db
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    return $dbh->selectrow_array("SELECT COUNT(*) FROM sysban " .
                                 "WHERE status='active' AND what=? AND value=? " .
                                 "AND NOW() > bandate " .
                                 "AND (NOW() < banuntil OR banuntil=0 OR banuntil IS NULL)",
                                 undef, $what, $value);
}

# <LJFUNC>
# name: LJ::sysban_note
# des: Inserts a properly-formatted row into statushistory noting that a ban has been triggered
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available
# des-notes: A very brief description of what triggered the ban
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values
# returns: nothing
# </LJFUNC>
sub sysban_note
{
    my ($userid, $notes, $vars) = @_;

    $notes .= ":";
    map { $notes .= " $_=$vars->{$_};" if $vars->{$_} } sort keys %$vars;
    LJ::statushistory_add($userid, 0, 'sysban_trig', $notes);
    return;
}

# <LJFUNC>
# name: LJ::sysban_block
# des: Notes a sysban in statushistory and returns a fake http error message to the user
# args: userid?, notes, vars
# des-userid: The userid which triggered the ban, if available
# des-notes: A very brief description of what triggered the ban
# des-vars: A hashref of helpful variables to log, keys being variable name and values being values
# returns: nothing
# </LJFUNC>
sub sysban_block
{
    my ($userid, $notes, $vars) = @_;

    LJ::sysban_note($userid, $notes, $vars);

    my $msg = <<'EOM';
<html>
<head>
<title>503 Service Unavailable</title>
</head>
<body>
<h1>503 Service Unavailable</h1>
The service you have requested is temporarily unavailable.
</body>
</html>
EOM

    BML::http_response(200, $msg);
    return;
}

# <LJFUNC>
# name: LJ::load_userpics
# des: Loads a bunch of userpic at once.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: arrayref of picids to load
# </LJFUNC>
sub load_userpics
{
    &nodb;
    my ($upics, $idlist) = @_;

    my @load_list;
    foreach my $id (@{$idlist})
    {
        if ($LJ::CACHE_USERPIC_SIZE{$id}) {
            $upics->{$id}->{'width'} = $LJ::CACHE_USERPIC_SIZE{$id}->[0];
            $upics->{$id}->{'height'} = $LJ::CACHE_USERPIC_SIZE{$id}->[1];
            $upics->{$id}->{'userid'} = $LJ::CACHE_USERPIC_SIZE{$id}->[2];
        } elsif ($id+0) {
            push @load_list, ($id+0);
        }
    }
    return unless @load_list;

    if (@LJ::MEMCACHE_SERVERS) {
        my @mem_keys = map { [$_,"userpic.$_"] } @load_list;
        my $mem = LJ::MemCache::get_multi(@mem_keys) || {};
        while (my ($k, $v) = each %$mem) {
            next unless $v && $k =~ /(\d+)/;
            my $id = $1;
            $upics->{$id}->{'width'} = $v->[0];
            $upics->{$id}->{'height'} = $v->[1];
            $upics->{$id}->{'userid'} = $v->[2];
        }
        @load_list = grep { ! $upics->{$_} } @load_list;
        return unless @load_list;
    }

    my $dbr = LJ::get_db_reader();
    my $picid_in = join(",", @load_list);
    my $sth = $dbr->prepare("SELECT userid, picid, width, height ".
                            "FROM userpic WHERE picid IN ($picid_in)");
    $sth->execute;
    while ($_ = $sth->fetchrow_hashref) {
        my $id = $_->{'picid'};
        undef $_->{'picid'};
        $upics->{$id} = $_;
        my $val = [ $_->{'width'}, $_->{'height'}, $_->{'userid'} ];
        $LJ::CACHE_USERPIC_SIZE{$id} = $val;
        LJ::MemCache::set([$id,"userpic.$id"], $val);
    }
}

# <LJFUNC>
# name: LJ::activate_userpics
# des: Sets/unsets userpics as inactive based on account caps
# args: u
# returns: nothing
# </LJFUNC>
sub activate_userpics
{
    # this behavior is optional, but enabled by default
    return if $LJ::ALLOW_PICS_OVER_QUOTA;

    my $u = shift;
    return unless $u;

    # get a database handle for reading/writing
    # need to get this now so we can pass it to load_userid if necessary
    my $dbh = LJ::get_db_writer();    

    # if a userid was given, get a real $u object
    $u = LJ::load_userid($dbh, $u, 1) unless ref $u eq "HASH";

    # should have a $u object now
    return unless ref $u eq 'HASH';
    my $userid = $u->{'userid'};

    # active / inactive lists
    my @active = ();
    my @inactive = ();
    my $allow = LJ::get_cap($u, "userpics");

    # get database cluster reader handle
    my $dbcr = LJ::get_cluster_reader($u);
    return unless $dbcr;

    # select all userpics and build active / inactive lists
    my $sth = $dbh->prepare("SELECT picid, state FROM userpic WHERE userid=?");
    $sth->execute($userid);
    while (my ($picid, $state) = $sth->fetchrow_array) {
        if ($state eq 'I') {
            push @inactive, $picid;
        } else {
            push @active, $picid;
        }
    }  

    # inactivate previously activated userpics
    if (@active > $allow) {
        my $to_ban = @active - $allow;

        # find first jitemid greater than time 2 months ago using rlogtime index
        # ($LJ::EndOfTime - UnixTime)
        my $jitemid = $dbcr->selectrow_array("SELECT jitemid FROM log2 USE INDEX (rlogtime) " .
                                             "WHERE journalid=? AND rlogtime > ? LIMIT 1",
                                             undef, $userid, $LJ::EndOfTime - time() + 86400*60);

        # query all pickws in logprop2 with jitemid > that value
        my %count_kw = ();
        my $propid = LJ::get_prop("log", "picture_keyword")->{'id'};
        my $sth = $dbcr->prepare("SELECT value, COUNT(*) FROM logprop2 " . 
                                 "WHERE journalid=? AND jitemid > ? AND propid=?" .
                                 "GROUP BY value");
        $sth->execute($userid, $jitemid, $propid);
        while (my ($value, $ct) = $sth->fetchrow_array) {
            # keyword => count
            $count_kw{$value} = $ct;
        }

        my $keywords_in = join(",", map { $dbcr->quote($_) } keys %count_kw);

        # map pickws to picids for freq hash below
        my %count_picid = ();
        if ($keywords_in) {
            my $sth = $dbcr->prepare("SELECT k.keyword, m.picid FROM keywords k, userpicmap m " .
                                     "WHERE k.keyword IN ($keywords_in) AND k.kwid=m.kwid " . 
                                     "AND m.userid=?");
            $sth->execute($userid);
            while (my ($keyword, $picid) = $sth->fetchrow_array) {
                # keyword => picid
                $count_picid{$picid} += $count_kw{$keyword};
            }
        }

        # we're only going to ban the least used, excluding the user's default
        my @ban = (grep { $_ != $u->{'defaultpicid'} } 
                   sort { $count_picid{$a} <=> $count_picid{$b} } @active);

        @ban = splice(@ban, 0, $to_ban) if @ban > $to_ban;
        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        $dbh->do("UPDATE userpic SET state='I' WHERE userid=? AND picid IN ($ban_in)", 
                 undef, $userid) if $ban_in;
    }

    # activate previously inactivated userpics
    if (@inactive && @active < $allow) {
        my $to_activate = $allow - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        $dbh->do("UPDATE userpic SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                 undef, $userid) if $activate_in;
    }

    return;
}

# <LJFUNC>
# name: LJ::get_pic_from_keyword
# des: Given a userid and keyword, returns the pic row hashref
# args: u, keyword
# des-keyword: The keyword of the userpic to fetch
# returns: hashref of pic row found
# </LJFUNC>
sub get_pic_from_keyword
{
    my $u = shift;
    my $userid = want_userid($u);
    my $keyword = shift;
    return undef unless $userid && $keyword;

    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    return $dbr->selectrow_hashref("SELECT p.* FROM userpic p, userpicmap m, keywords k " .
                                   "WHERE k.kwid=m.kwid AND p.picid=m.picid AND m.userid=? AND k.keyword=?",
                                   undef, $userid, $keyword);

}


# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.  Character set will only be used if message is not ascii.
# args: opt
# des-opt: Hashref of arguments.  <b>Required:</b> to, from, subject, body.
#          <b>Optional:</b> toname, fromname, cc, bcc, charset
# </LJFUNC>
sub send_mail
{
    my $opt = shift;

    my $clean_name = sub {
        my $name = shift;
        $name =~ s/[\n\t\(\)]//g;
        return $name ? " ($name)" : "";
    };

    my $msg = new MIME::Lite ('From' => "$opt->{'from'}" . $clean_name->($opt->{'fromname'}),
                              'To' => "$opt->{'to'}" . $clean_name->($opt->{'toname'}),
                              'Cc' => $opt->{'cc'},
                              'Bcc' => $opt->{'bcc'},
                              'Subject' => $opt->{'subject'},
                              'Data' => $opt->{'body'});

    if ($opt->{'charset'} && ! (LJ::is_ascii($opt->{'body'}) && LJ::is_ascii($opt->{'subject'}))) {
        $msg->attr("content-type.charset" => $opt->{'charset'});        
    }

    return eval { $msg->send; 1; }
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
        'eat' => [qw[layer iframe script object embed]],
        'mode' => 'allow',
        'keepcomments' => 1, # Allows CSS to work
    });
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
# name: LJ::robot_meta_tags
# des: Returns meta tags to block a robot from indexing or following links
# returns: A string with appropriate meta tags
# </LJFUNC>
sub robot_meta_tags
{
    return "<meta name=\"robots\" content=\"noindex, nofollow, noarchive\" />\n" .
           "<meta name=\"googlebot\" content=\"nosnippet\" />\n";
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
    &nodb;
    my ($user, $view, $remote, $opts) = @_;

    my $r = $opts->{'r'};  # mod_perl $r, or undef
    my $geta = $opts->{'getargs'};

    if ($LJ::SERVER_DOWN) {
        if ($opts->{'vhost'} eq "customview") {
            return "<!-- LJ down for maintenance -->";
        }
        return LJ::server_down_html();
    }

    # S1 style hashref.  won't be loaded now necessarily, 
    # only if via customview.
    my $style;

    my ($styleid);
    if ($opts->{'styleid'}) {  # s1 styleid
        $styleid = $opts->{'styleid'}+0;

        # if we have an explicit styleid, we have to load
        # it early so we can learn its type, so we can
        # know which uprops to load for its owner
        $style = LJ::S1::load_style($styleid, \$view);
    } else {
        $view ||= "lastn";    # default view when none specified explicitly in URLs
        if ($LJ::viewinfo{$view} || $view eq "month" || 
            $view eq "entry" || $view eq "reply")  {
            $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
        } else {
            $opts->{'badargs'} = 1;
        }
    }
    return unless $styleid;

    my $u;
    if ($opts->{'u'}) {
        $u = $opts->{'u'};
    } else {
        $u = LJ::load_user($user);
    }

    unless ($u) {
        $opts->{'baduser'} = 1;
        return "<h1>Error</h1>No such user <b>$user</b>";
    }

    my $eff_view = $LJ::viewinfo{$view}->{'styleof'} || $view;
    my $s1prop = "s1_${eff_view}_style";

    my @needed_props = ("stylesys", "s2_style", "url", "urlname", $s1prop, "opt_nctalklinks",
                        "renamedto",  "opt_blockrobots", "opt_usesharedpic",
                        "journaltitle", "journalsubtitle");

    # preload props the view creation code will need later (combine two selects)
    if (ref $LJ::viewinfo{$eff_view}->{'owner_props'} eq "ARRAY") {
        push @needed_props, @{$LJ::viewinfo{$eff_view}->{'owner_props'}};
    }

    if ($eff_view eq "reply") {
        push @needed_props, "opt_logcommentips";
    }

    LJ::load_user_props($u, { 'cache' => 1 }, @needed_props);

    # if the remote is the user to be viewed, make sure the $remote
    # hashref has the value of $u's opt_nctalklinks (though with
    # LJ::load_user caching, this may be assigning between the same
    # underlying hashref)
    $remote->{'opt_nctalklinks'} = $u->{'opt_nctalklinks'} if
        ($remote && $remote->{'userid'} == $u->{'userid'});

    my $stylesys = 1;
    if ($styleid == -1) {
        # force s2 style id
        if ($opts->{'s2id'}) {
            $stylesys = 2;
            $styleid = $opts->{'s2id'};
        } elsif ($view eq "res" && $opts->{'pathextra'} =~ m!^/(\d+)/!) {
            # resource URLs have the styleid in it
            $stylesys = 2;
            $styleid = $1;
        } elsif ($u->{'stylesys'} == 2) {
            $stylesys = 2;
            $styleid = $u->{'s2_style'};
        } else {
            $styleid = $u->{$s1prop};    
            LJ::run_hooks("s1_style_select", {
                'styleid' => \$styleid,
                'u' => $u,
                'view' => $view,
            });
        }
    }

    # signal to LiveJournal.pm that we can't handle this
    if ($stylesys == 1 && ($view eq "entry" || $view eq "reply" || $view eq "month")) {
        ${$opts->{'handle_with_bml_ref'}} = 1;
        return;
    }

    if ($r) {
        $r->notes('journalid' => $u->{'userid'});
    }
    
    my $notice = sub {
        my $msg = shift;
        my $url = "$LJ::SITEROOT/users/$user/";
        return qq{
            <h1>Notice</h1>
            <p>$msg</p>
            <p>Instead, please use <nobr><a href=\"$url\">$url</a></nobr></p>
        };
    };
    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && $u->{'journaltype'} ne 'R' &&
        ! LJ::get_cap($u, "userdomain")) {
        return $notice->("URLs like <nobr><b>http://<i>username</i>.$LJ::USER_DOMAIN/" .
                         "</b></nobr> are not available for this user's account type.");
    }
    if ($opts->{'vhost'} =~ /^other:/ && ! LJ::get_cap($u, "userdomain")) {
        return $notice->("This user's account type doesn't permit domain aliasing.");
    }
    if ($opts->{'vhost'} eq "customview" && ! LJ::get_cap($u, "styles")) {
        return $notice->("This user's account type is not permitted to create and embed styles.");
    }
    if ($opts->{'vhost'} eq "community" && $u->{'journaltype'} ne "C") {
        $opts->{'badargs'} = 1; # Output a generic 'bad URL' message if available
        return "<h1>Notice</h1><p>This account isn't a community journal.</p>";
    }
    if ($view eq "friendsfriends" && ! LJ::get_cap($u, "friendsfriendsview")) {
        return "<b>Sorry</b><br />This user's account type doesn't permit showing friends of friends.";
    }

    return "<h1>Error</h1>Journal has been deleted.  If you are <b>$user</b>, you have a period of 30 days to decide to undelete your journal." if ($u->{'statusvis'} eq "D");
    return "<h1>Error</h1>This journal has been suspended." if ($u->{'statusvis'} eq "S");
    return "<h1>Error</h1>This journal has been deleted and purged." if ($u->{'statusvis'} eq "X");

    $opts->{'view'} = $view;

    # what charset we put in the HTML
    $opts->{'saycharset'} ||= "utf-8";

    if ($stylesys == 2 && $view ne 'rss') {
        $r->notes('codepath' => "s2.$view") if $r;
        return LJ::S2::make_journal($u, $styleid, $view, $remote, $opts);
    }

    $r->notes('codepath' => "s1.$view") if $r;

    # load the user-related S1 data  (overrides and colors)
    my $s1uc = {};
    my $s1uc_memkey = [$u->{'userid'}, "s1uc:$u->{'userid'}"];
    if ($u->{'useoverrides'} eq "Y" || $u->{'themeid'} == 0) {
        $s1uc = LJ::MemCache::get($s1uc_memkey);
        unless ($s1uc) {
            my $dbcr = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_master($u) : LJ::get_cluster_reader($u);
            $s1uc = $dbcr->selectrow_hashref("SELECT * FROM s1usercache WHERE userid=?",
                                             undef, $u->{'userid'});
            LJ::MemCache::set($s1uc_memkey, $s1uc) if $s1uc;
        }
    }

    # we should have our cache row!  we'll update it in a second.
    my $dbcm;
    if (! $s1uc) {
        $dbcm ||= LJ::get_cluster_master($u);
        $dbcm->do("INSERT IGNORE INTO s1usercache (userid) VALUES (?)", undef, $u->{'userid'});
        $s1uc = {};
    }
    
    # conditionally rebuild parts of our cache that are missing
    my %update;

    # is the overrides cache old or missing?
    if ($u->{'useoverrides'} eq "Y" && (! $s1uc->{'override_stor'} ||
                                        $s1uc->{'override_cleanver'} < $LJ::S1::CLEANER_VERSION)) {
        $dbcm ||= LJ::get_cluster_master($u);
        my $dbh = LJ::get_db_writer();
        my $overrides = $dbh->selectrow_array("SELECT override FROM overrides WHERE user=?",
                                              undef, $u->{'user'});
        $update{'override_stor'} = LJ::CleanHTML::clean_s1_style($overrides);
        $update{'override_cleanver'} = $LJ::S1::CLEANER_VERSION;
    }
     
    # is the color cache here if it's a custom user theme?
    if ($u->{'themeid'} == 0 && ! $s1uc->{'color_stor'}) {
        my $col = {};
        my $dbh = LJ::get_db_writer();
        my $sth = $dbh->prepare("SELECT coltype, color FROM themecustom WHERE user=?");
        $sth->execute($u->{'user'});
        $col->{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
        $update{'color_stor'} = Storable::freeze($col);
    }

    # save the updates
    if (%update) {
        my $set;
        $dbcm ||= LJ::get_cluster_master($u);
        foreach my $k (keys %update) {
            $s1uc->{$k} = $update{$k};
            $set .= ", " if $set;
            $set .= "$k=" . $dbcm->quote($update{$k});
        }
        my $rv = $dbcm->do("UPDATE s1usercache SET $set WHERE userid=?", undef, $u->{'userid'});
        if ($rv && $update{'color_stor'}) {
            my $dbh = LJ::get_db_writer();
            $dbh->do("DELETE FROM themecustom WHERE user=?", undef, $u->{'user'});
        }
        LJ::MemCache::set($s1uc_memkey, $s1uc);
    }

    # load the style
    my $viewref = $view eq "" ? \$view : undef;
    $style ||= $LJ::viewinfo{$view}->{'nostyle'} ? {} :
        LJ::S1::load_style($styleid, $viewref);

    my %vars = ();
    
    # apply the style
    foreach (keys %$style) {
        $vars{$_} = $style->{$_};
    }

    # apply the overrides
    if ($opts->{'nooverride'}==0 && $u->{'useoverrides'} eq "Y") {
        my $tw = Storable::thaw($s1uc->{'override_stor'});
        foreach (keys %$tw) {
            $vars{$_} = $tw->{$_};
        }
    }

    # apply the color theme
    my $cols = $u->{'themeid'} ? LJ::S1::get_themeid($u->{'themeid'}) :
        Storable::thaw($s1uc->{'color_stor'});
    foreach (keys %$cols) {
        $vars{"color-$_"} = $cols->{$_};
    }
        
    # instruct some function to make this specific view type
    return unless defined $LJ::viewinfo{$view}->{'creator'};
    my $ret = "";

    # call the view creator w/ the buffer to fill and the construction variables
    my $res = $LJ::viewinfo{$view}->{'creator'}->(\$ret, $u, \%vars, $remote, $opts);

    unless ($res) {
        my $errcode = $opts->{'errcode'};
        my $errmsg = {
            'nodb' => 'Database temporarily unavailable during maintenance.',
            'nosyn' => 'No syndication URL available.',
        }->{$errcode};
        return "<!-- $errmsg -->" if ($opts->{'vhost'} eq "customview");
        return $errmsg;
    }   

    if ($opts->{'redir'}) {
        return undef;
    }

    # clean up attributes which we weren't able to quickly verify
    # as safe in the Storable-stored clean copy of the style.
    $ret =~ s/\%\%\[attr\[(.+?)\]\]\%\%/LJ::CleanHTML::s1_attribute_clean($1)/eg;

    # return it...
    return $ret;
}

sub syn_cost
{
    my $watchers = shift;
    return 1/(log($watchers)/log(5)+1);
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
    if ($LJ::DEBUG{'get_dbs'}) {
        my $errmsg = "sloppy use of LJ::get_dbs() ?\n";
        my $i = 0;
        while (my ($p, $f, $l) = caller($i++)) {
            next if $i > 3;
            $errmsg .= "  $p, $f, $l\n";
        }
        warn $errmsg;
    }
    return $LJ::REQ_CACHE_DBS{0} if $LJ::REQ_CACHE_DBS{0};

    my $dbh = LJ::get_dbh("master");
    my $dbr = LJ::get_dbh("slave");

    # check to see if fdsns of connections we just got match.  if
    # slave ends up being master, we want to pretend we just have no
    # slave (avoids some queries being run twice on master).  this is
    # common when somebody sets up a master and 2 slaves, but has the
    # master doing 1 of the 3 configured slave roles
    $dbr = undef if $LJ::DBIRole->same_cached_handle("slave", "master");

    return $LJ::REQ_CACHE_DBS{0} = make_dbs($dbh, $dbr);
}

sub get_db_reader {
    return LJ::get_dbh("slave", "master");
}

sub get_db_writer {
    return LJ::get_dbh("master");
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
    my @roles = ("cluster${id}slave", "cluster${id}");
    return LJ::get_dbh(@roles);
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
    my $role = "cluster${id}";
    return LJ::get_dbh($role);
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
    return $LJ::REQ_CACHE_DBS{$id} if $LJ::REQ_CACHE_DBS{$id};
    my $dbs = {};
    $dbs->{'dbh'} = LJ::get_dbh("cluster${id}");
    $dbs->{'dbr'} = LJ::get_dbh("cluster${id}slave");

    # see note in LJ::get_dbs about why we do this:
    $dbs->{'dbr'} = undef
        if $LJ::DBIRole->same_cached_handle("cluster${id}", "cluster${id}slave");

    $dbs->{'has_slave'} = defined $dbs->{'dbr'};
    $dbs->{'reader'} = $dbs->{'has_slave'} ? $dbs->{'dbr'} : $dbs->{'dbh'};
    bless $dbs, "LJ::DBSet";
    return $LJ::REQ_CACHE_DBS{$id} = $dbs;
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
    bless $dbs, "LJ::DBSet";
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
    if (ref($dbarg) eq "HASH" || ref($dbarg) eq "LJ::DBSet") {
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
    return unless $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;

    my ($y, $m, $d) = ($1, $2, $3);
    my ($nm, $nd) = ($m+0, $d+0);   # numeric, without leading zeros
    my $user = $u->{'user'};
    my $base = LJ::journal_base($u);

    my $ret;
    $ret .= "<a href=\"$base/$y/\">$y</a>-";
    $ret .= "<a href=\"$base/$y/$m/\">$m</a>-";
    $ret .= "<a href=\"$base/$y/$m/$d/\">$d</a>";
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
    my $ditemid = $itemid*256 + $anum;
    return LJ::journal_base($u) . "/$ditemid.html";
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
    &nodb;
    my $ditemid = shift;
    my $remote = shift;
    my $eventref = shift;

    LJ::Poll::show_polls($ditemid, $remote, $eventref);
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

sub update_user
{
    my ($uuserid, $ref) = @_;
    my $uid = want_userid($uuserid);
    return 0 unless $uid;

    my @sets;
    my @bindparams;
    while (my ($k, $v) = each %$ref) {
        if ($k eq "raw") {
            push @sets, $v;
        } else {
            push @sets, "$k=?";
            push @bindparams, $v;
        }
    }
    return 1 unless @sets;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;
    { 
        local $" = ",";
        $dbh->do("UPDATE user SET @sets WHERE userid=?", undef,
                 @bindparams, $uid);
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        my $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE userid=?", undef, $uid);
        LJ::memcache_set_u($u);
    }
    return 1;
}

# <LJFUNC>
# name: LJ::load_userids_multiple
# des: Loads a number of users at once, efficiently.
# info: loads a few users at once, their userids given in the keys of $map
#       listref (not hashref: can't have dups).  values of $map listref are
#       scalar refs to put result in.  $have is an optional listref of user
#       object caller already has, but is too lazy to sort by themselves.
# args: dbarg?, map, have
# des-map: Arrayref of pairs (userid, destination scalarref)
# des-have: Arrayref of user objects caller already has
# returns: Nothing.
# </LJFUNC>
sub load_userids_multiple
{
    &nodb;
    my ($map, $have) = @_;

    my $sth;

    my %need;
    while (@$map) {
        my $id = shift @$map;
        my $ref = shift @$map;
        push @{$need{$id}}, $ref;

        if ($LJ::REQ_CACHE_USER_ID{$id}) {
            push @{$have}, $LJ::REQ_CACHE_USER_ID{$id};
        }
    }

    my $satisfy = sub {
        my $u = shift;
        next unless ref $u eq "HASH";
        foreach (@{$need{$u->{'userid'}}}) {
            $$_ = $u;
        }
        $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u;
        $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u;
        delete $need{$u->{'userid'}};
    };

    if ($have) {
        foreach my $u (@$have) {
            $satisfy->($u);
        }
    }
    
    if (%need) {
        my $mem = LJ::MemCache::get_multi(map { [$_,"userid:$_"] } keys %need) || {};
        $satisfy->($_) foreach (values %$mem);
    }

    if (%need) {
        my $in = join(", ", map { $_+0 } keys %need);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        ($sth = $db->prepare("SELECT * FROM user WHERE userid IN ($in)"))->execute;
        while (my $u = $sth->fetchrow_hashref) {
            LJ::memcache_set_u($u);
            $satisfy->($u); 
          }
    }
}

# <LJFUNC>
# name: LJ::load_user
# des: Loads a user record given a username.
# info: From the [dbarg[user]] table.
# args: dbarg?, user, force?
# des-user: Username of user to load.
# des-force: if set to true, won't return cached user object
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_user
{
    my $db;
    if (ref $_[0]) {
        my $dbarg = shift;
        my $dbs = LJ::make_dbs_from_arg($dbarg);
        $db = $dbs->{'dbh'};
    }
    my ($user, $force) = @_;

    $user = LJ::canonical_username($user);
    return undef unless length $user;
    
    return $LJ::REQ_CACHE_USER_NAME{$user} if
        $LJ::REQ_CACHE_USER_NAME{$user} && ! $force;

    my $u = LJ::MemCache::get("user:$user");

    # try a reader, unless we're using memcache, otherwise we'll wait and
    # load from master below.
    unless ($u || @LJ::MEMCACHE_SERVERS) {
        $db ||= LJ::get_db_reader();
        $u = $db->selectrow_hashref("SELECT * FROM user WHERE user=?", undef, $user);
    }

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    unless ($u) {
        my $dbh = LJ::get_db_writer();
        if (ref $LJ::AUTH_EXISTS eq "CODE") {
            if ($LJ::AUTH_EXISTS->($user)) {
                if (LJ::create_account($dbh, {
                    'user' => $user,
                    'name' => $user,
                    'password' => "",
                }))
                {
                    # NOTE: this should pull from the master, since it was _just_
                    # created and the elsif below won't catch.
                    return $dbh->selectrow_hashref("SELECT * FROM user WHERE user=?", undef, $user);
                } else {
                    return undef;
                }
            }
        } else {
            # If the user still doesn't exist, and there isn't an alternate auth code
            # try grabbing it from the master.
            $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE user=?", undef, $user);
            LJ::memcache_set_u($u) if $u;
        }
    }

    $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u if $u;
    $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u if $u;
    return $u;
}

sub memcache_set_u
{
    my $u = shift;
    return unless $u;
    my $expire = time() + 1800;
    LJ::MemCache::set([$u->{'userid'}, "userid:$u->{'userid'}"], $u, $expire);
    LJ::MemCache::set("user:$u->{'user'}", $u, $expire);
}

# <LJFUNC>
# name: LJ::load_userid
# des: Loads a user record given a userid.
# info: From the [dbarg[user]] table.
# args: dbarg?, userid, force?
# des-userid: Userid of user to load.
# des-force: If set to true, won't return cached user object.
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_userid
{
    my $dbarg = ref $_[0] ? shift : undef;
    my ($userid, $force) = @_;
    return undef unless $userid;
    
    return $LJ::REQ_CACHE_USER_ID{$userid} if
        $LJ::REQ_CACHE_USER_ID{$userid} && ! $force;

    my $u = LJ::MemCache::get([$userid,"userid:$userid"]);

    unless ($u) {
        my $master = 0;
        unless ($dbarg) {
            $dbarg = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
            $master = @LJ::MEMCACHE_SERVERS ? 1 : 0;
        }

        my $dbs = LJ::make_dbs_from_arg($dbarg);
        my $db = $dbs->{'reader'};

        $u = $db->selectrow_hashref("SELECT * FROM user WHERE userid=?", undef, 
                                    $userid);
        LJ::memcache_set_u($u) if $u && $master;
            
        if (!$u && ($dbs->{'has_slave'} || !$dbarg)) {
            my $dbh = $dbarg ? $dbs->{'dbh'} : LJ::get_db_writer();
            $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE userid=?", undef, $userid);
        }
    }

    $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u if $u;
    $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u if $u;
    return $u;
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
    return if $LJ::CACHED_MOODS;
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT moodid, mood, parentmood FROM moods");
    $sth->execute;
    while (my ($id, $mood, $parent) = $sth->fetchrow_array) {
        $LJ::CACHE_MOODS{$id} = { 'name' => $mood, 'parent' => $parent };
        if ($id > $LJ::CACHED_MOOD_MAX) { $LJ::CACHED_MOOD_MAX = $id; }
    }
    $LJ::CACHED_MOODS = 1;
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

    my $mode = "run";
    if ($cmd =~ s/:(\w+)//) {
        $mode = $1;
    } 

    # built-in commands
    my $cmds = {
        'delitem' => {
            'run' => sub {
                my ($dbh, $db, $c) = @_;
                my $a = $c->{'args'};
                LJ::delete_item2($db, $c->{'journalid'}, $a->{'itemid'},
                                 0, $a->{'anum'});
            },
        },
        # ping weblogs.com with updates?  takes a $u argument
        'weblogscom' => {
            'run' => sub {
                # user, title, url
                my ($dbh, $db, $c) = @_;
                my $a = $c->{'args'};
                my $unixtime = LJ::mysqldate_to_time($c->{'instime'});
                # if more than 6 hours old (qbufferd not running?)
                return if $unixtime < time() - 60*60*6;
                eval {
                    eval "use XMLRPC::Lite;";
                    XMLRPC::Lite
                        ->new( proxy => "http://rpc.weblogs.com/RPC2",
                               timeout => 5 )
                        ->call('weblogUpdates.ping', # xml-rpc method call
                               LJ::ehtml($a->{'title'}),
                               $a->{'url'},
                               "$LJ::SITEROOT/misc/weblogs-change.bml?user=$a->{'user'}");
                };
            },
        },
    };

    my $code;

    # is it a built-in command?
    if ($cmds->{$cmd}) {
        $code = $cmds->{$cmd}->{$mode};

    # otherwise it might be a site-local command
    } else {
        $code = $LJ::HOOKS{"cmdbuf:$cmd:$mode"}->[0]
            if $LJ::HOOKS{"cmdbuf:$cmd:$mode"};
    }

    return 0 unless $code;

    # start/finish modes
    if ($mode ne "run") {
        $code->($dbh);
        return;
    }

    my $clist;
    my $loop = 1;

    my $where = "cmd=" . $dbh->quote($cmd);
    if ($userid) {
        $where .= " AND journalid=" . $dbh->quote($userid);
    }

    my $LIMIT = 30;

    while ($loop &&
           ($clist = $db->selectcol_arrayref("SELECT cbid FROM cmdbuffer ".
                                             "WHERE $where ORDER BY cbid LIMIT $LIMIT")) &&
           $clist && @$clist)
    {
        foreach my $cbid (@$clist) {
            my $got_lock = $db->selectrow_array("SELECT GET_LOCK('cbid-$cbid',10)");
            return 0 unless $got_lock;
            # FIXME: why don't we just load the whole row above?
            my $c = $db->selectrow_hashref("SELECT * FROM cmdbuffer WHERE cbid=$cbid");
            next unless $c;

            my $a = {};
            LJ::decode_url_string($c->{'args'}, $a);
            $c->{'args'} = $a;
            $code->($dbh, $db, $c);

            $db->do("DELETE FROM cmdbuffer WHERE cbid=$cbid");
            $db->do("SELECT RELEASE_LOCK('cbid-$cbid')");
        }
        $loop = 0 unless scalar(@$clist) == $LIMIT;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::journal_base
# des: Returns URL of a user's journal.
# info: The tricky thing is that users with underscores in their usernames
#       can't have some_user.site.com as a hostname, so that's changed into
#       some-user.site.com.
# args: uuser, vhost?
# des-uuser: User hashref or username of user whose URL to make.
# des-vhost: What type of URL.  Acceptable options are "users", to make a
#            http://user.site.com/ URL; "tilde" to make http://site.com/~user/;
#            "community" for http://site.com/community/user; or the default
#            will be http://site.com/users/user.  If unspecifed and uuser
#            is a user hashref, then the best/preferred vhost will be chosen.
# returns: scalar; a URL.
# </LJFUNC>
sub journal_base
{
    my ($user, $vhost) = @_;
    if (ref $user eq "HASH") {
        my $u = $user;
        $user = $u->{'user'};
        unless (defined $vhost) {
            if ($LJ::FRONTPAGE_JOURNAL eq $user) {
                $vhost = "front";
            } elsif ($u->{'journaltype'} eq "P") {
                $vhost = "";
            } elsif ($u->{'journaltype'} eq "C") {
                $vhost = "community";
            }

        }
    }
    if ($vhost eq "users") {
        my $he_user = $user;
        $he_user =~ s/_/-/g;
        return "http://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
        return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
        return "$LJ::SITEROOT/community/$user";
    } elsif ($vhost eq "front") {
        return $LJ::SITEROOT;
    } elsif ($vhost =~ /^other:(.+)/) {
        return "http://$1";
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
    &nodb;
    my $remote = shift;
    my @privs = @_;
    return unless $remote and @privs;

    # return if we've already loaded these privs for this user.
    @privs = grep { ! $remote->{'_privloaded'}->{$_} } @privs;
    return unless @privs;

    my $dbr = LJ::get_db_reader();
    return unless $dbr;
    foreach (@privs) { $remote->{'_privloaded'}->{$_}++; }
    @privs = map { $dbr->quote($_) } @privs;
    my $sth = $dbr->prepare("SELECT pl.privcode, pm.arg ".
                            "FROM priv_map pm, priv_list pl ".
                            "WHERE pm.prlid=pl.prlid AND ".
                            "pl.privcode IN (" . join(',',@privs) . ") ".
                            "AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    while (my ($priv, $arg) = $sth->fetchrow_array) {
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
# args: dbarg?, u, priv, arg?
# des-priv: Priv name to check for (see [dbtable[priv_list]])
# des-arg: Optional argument.  If defined, function only returns true
#          when $remote has a priv of type $priv also with arg $arg, not
#          just any priv of type $priv, which is the behavior without
#          an $arg
# returns: boolean; true if user has privilege
# </LJFUNC>
sub check_priv
{
    &nodb;
    my ($u, $priv, $arg) = @_;
    return 0 unless $u;

    if (! $u->{'_privloaded'}->{$priv}) {
	LJ::load_user_privs($u, $priv);
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
    shift if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db";
    my $remote = shift;
    my $privcode = shift;     # required.  priv code to check for.
    my $ref = shift;  # optional, arrayref or hashref to populate
    return 0 unless ($remote);

    ### authentication done.  time to authorize...

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT pm.arg FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode=? AND pm.userid=?");
    $sth->execute($privcode, $remote->{'userid'});

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
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_userid
{
    my $dbarg = ref $_[0] ? shift : undef;
    my $user = shift;

    $user = LJ::canonical_username($user);

    my $userid;
    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $dbr;
    if ($dbarg) {
        my $dbs = LJ::make_dbs_from_arg($dbarg);
        $dbr = $dbs->{'reader'};
    } else {
        $dbr = LJ::get_db_reader();
    }

    my $quser = $dbr->quote($user);
    my $sth = $dbr->prepare("SELECT userid FROM useridmap WHERE user=$quser");
    $sth->execute;
    ($userid) = $sth->fetchrow_array;
    if ($userid) { $LJ::CACHE_USERID{$user} = $userid; }

    # implictly create an account if we're using an external
    # auth mechanism
    if (! $userid && ref $LJ::AUTH_EXISTS eq "CODE")
    {
        my $dbh = LJ::get_db_writer();
        $userid = LJ::create_account($dbh, { 'user' => $user,
                                             'name' => $user,
                                             'password' => '', });
    }

    return ($userid+0);
}

# <LJFUNC>
# name: LJ::want_userid
# des: Returns userid when passed either userid or the user hash. Useful to functions that
#      want to accept either. Forces its return value to be a number (for safety).
# args: userid
# des-userid: Either a userid, or a user hash with the userid in its 'userid' key.
# returns: The userid, guaranteed to be a numeric value.
# </LJFUNC>
sub want_userid
{
    my $uuserid = shift;
    return ($uuserid->{'userid'} + 0) if ref $uuserid;
    return ($uuserid + 0);
}


# <LJFUNC>
# name: LJ::get_username
# des: Returns a username given a userid.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_userid]].
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_username
{
    my $dbarg = ref $_[0] ? shift : undef;
    my $userid = shift;
    $userid += 0;

    # Checked the cache first.
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    my $dbr;
    my $dbs;
    if ($dbarg) {
        $dbs = LJ::make_dbs_from_arg($dbarg);
        $dbr = $dbs->{'reader'};
    } else {
        $dbr = LJ::get_db_reader();
    }

    my $user = $dbr->selectrow_array("SELECT user FROM useridmap WHERE userid=$userid");

    # Fall back to master if it doesn't exist.
    if (! defined($user) && ($dbs->{'has_slave'} || ! $dbarg)) {
        my $dbh = $dbs ? $dbs->{'dbh'} : LJ::get_db_writer();
        $user = $dbr->selectrow_array("SELECT user FROM useridmap WHERE userid=$userid");
    }
    if (defined($user)) { $LJ::CACHE_USERNAME{$userid} = $user; }
    return ($user);
}

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
    &nodb;
    my $kw = shift;
    unless ($kw =~ /\S/) { return 0; }
    $kw = LJ::text_trim($kw, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD);

    my $dbh = LJ::get_db_writer();
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
    &nodb;
    my ($posterid, $reqownername, $res) = @_;

    my $qposterid = $posterid+0;

    ## find the journal owner's info
    my $uowner = LJ::load_user($reqownername);
    unless ($uowner) {
        $res->{'errmsg'} = "Journal \"$reqownername\" does not exist.";
        return 0;
    }
    my $ownerid = $uowner->{'userid'};

    # the 'ownerid' necessity came first, way back when.  but then
    # with clusters, everything needed to know more, like the
    # journal's dversion and clusterid, so now it also returns the
    # user row.
    $res->{'ownerid'} = $ownerid;
    $res->{'u_owner'} = $uowner;

    ## check if user has access
    return 1 if LJ::check_rel($ownerid, $qposterid, 'P');

    # let's check if this community is allowing post access to non-members 
    my $dbr = LJ::get_db_reader();
    LJ::load_user_props($dbr, $uowner, "nonmember_posting");
    if ($uowner->{'nonmember_posting'}) {
        my $postlevel = $dbr->selectrow_array("SELECT postlevel FROM ".
                                              "community WHERE userid=$ownerid");
        return 1 if $postlevel eq 'members';
    }

    $res->{'errmsg'} = "You do not have access to post to this journal.";
    return 0;
}

sub can_add_syndicated
{
    my ($u, $su) = @_;  # user and syndicated user
    my $quota = LJ::get_cap($u, "synd_quota");
    return 0 unless $quota;

    my $used;

    # see where we're
    my $dbh = LJ::get_dbh("master");
    my $sth = $dbh->prepare("SELECT s.userid, COUNT(*) FROM syndicated s, friends fa, friends fb ".
                            "WHERE fa.userid=? AND fa.friendid=s.userid  ".
                            "AND fb.friendid=s.userid GROUP BY 1");
    $sth->execute($u->{'userid'});
    while (my ($sid, $ct) = $sth->fetchrow_array) {
        # if user already has this friend, doesn't change their count to add it again.
        return 1 if ($sid == $su->{'userid'});
        $used += LJ::syn_cost($ct);
        return 0 if $used > $quota;
    }
    
    # they're under quota so far.  would this account push them over?
    my $ct = $dbh->selectrow_array("SELECT COUNT(*) FROM friends WHERE friendid=?", undef,
                                   $su->{'userid'});
    $used += LJ::syn_cost($ct + 1);
    return 0 if $used > $quota;
    return 1;
}

sub set_logprop
{
    my ($u, $jitemid, $hashref) = @_;  # hashref
    my $dbcm = LJ::get_cluster_master($u);

    $jitemid += 0;
    my $uid = $u->{'userid'} + 0;
    my $kill_mem = 0;
    my $del_ids;
    my $ins_values;
    while (my ($k, $v) = each %{$hashref||{}}) {
        my $prop = LJ::get_prop("log", $k);
        next unless $prop;
        $kill_mem = 1 unless $prop eq "commentalter";
        if ($v) {
            $ins_values .= "," if $ins_values;
            $ins_values .= "($uid, $jitemid, $prop->{'id'}, " . $dbcm->quote($v) . ")";
        } else {
            $del_ids .= "," if $del_ids;
            $del_ids .= $prop->{'id'};
        }
    }
    
    $dbcm->do("REPLACE INTO logprop2 (journalid, jitemid, propid, value) ".
              "VALUES $ins_values") if $ins_values;
    $dbcm->do("DELETE FROM logprop2 WHERE journalid=? AND jitemid=? ".
              "AND propid IN ($del_ids)", undef, $u->{'userid'}, $jitemid) if $del_ids;

    LJ::MemCache::delete([$uid,"logprop:$uid:$jitemid"]) if $kill_mem;
}

# <LJFUNC>
# name: LJ::load_log_props2
# class:
# des:
# info:
# args: db?, uuserid, listref, hashref
# des-:
# returns:
# </LJFUNC>
sub load_log_props2
{
    my $db = (ref $_[0] eq "DBI::db") ? shift @_ : undef;

    my ($uuserid, $listref, $hashref) = @_;
    my $userid = want_userid($uuserid);
    return unless ref $hashref eq "HASH";
    
    my %need;
    my @memkeys;
    foreach my $id (@$listref) {
        $id += 0;
        $need{$id} = 1;
        push @memkeys, [$userid,"logprop:$userid:$id"];
    }
    return unless %need;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        delete $need{$2};
        $hashref->{$2} = $v;
    }
    return unless %need;

    unless ($db) {
        my $u = LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_master($u) :  LJ::get_cluster_reader($u);
        return unless $db;
    }

    LJ::load_props("log");
    my $in = join(",", keys %need);
    my $sth = $db->prepare("SELECT jitemid, propid, value FROM logprop2 ".
                           "WHERE journalid=? AND jitemid IN ($in)");
    $sth->execute($userid);
    while (my ($jitemid, $propid, $value) = $sth->fetchrow_array) {
        $hashref->{$jitemid}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
    }
    foreach my $id (keys %need) {
        LJ::MemCache::set([$userid,"logprop:$userid:$id"], $hashref->{$id} || {});
    }
}

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
    &nodb;    
    # ids by cluster (hashref),  output hashref (keys = "$ownerid $jitemid")
    my ($idsbyc, $hashref) = @_;
    my $sth;
    return unless ref $idsbyc eq "HASH";
    LJ::load_props("log");

    my @memkeys;
    foreach my $c (keys %$idsbyc) {
        foreach my $pair (@{$idsbyc->{$c}}) {
            push @memkeys, [$pair->[0],"logprop:$pair->[0]:$pair->[1]"];
        }
    }
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        $hashref->{"$1 $2"} = $v;
    }

    foreach my $c (keys %$idsbyc) {
        my @need;
        foreach (@{$idsbyc->{$c}}) {
            next if $hashref->{"$_->[0] $_->[1]"};
            push @need, $_;
        }
        next unless @need;
        my $in = join(" OR ", map { "(journalid=" . ($_->[0]+0) . " AND jitemid=" . ($_->[1]+0) . ")" } @need);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_master($c) : LJ::get_cluster_reader($c);
        next unless $db;  # FIXME: do something better?
        $sth = $db->prepare("SELECT journalid, jitemid, propid, value ".
                            "FROM logprop2 WHERE $in");
        $sth->execute;
        while (my ($jid, $jitemid, $propid, $value) = $sth->fetchrow_array) {
            $hashref->{"$jid $jitemid"}->{$LJ::CACHE_PROPID{'log'}->{$propid}->{'name'}} = $value;
        }
        foreach my $pair (@need) {
            LJ::MemCache::set([$pair->[0], "logprop:$pair->[0]:$pair->[1]"],
                              $hashref->{"$pair->[0] $pair->[1]"} || {});
        }
    }
}

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
    my $db = (ref $_[0] eq "DBI::db") ? shift @_ : undef;
    my ($uuserid, $listref, $hashref) = @_;

    my $userid = want_userid($uuserid);
    return unless ref $hashref eq "HASH";

    my %need;
    my @memkeys;
    foreach my $id (@$listref) {
        $id += 0;
        $need{$id} = 1;
        push @memkeys, [$userid,"talkprop:$userid:$id"];
    }
    return unless %need;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};
    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        delete $need{$2};
        $hashref->{$2} = $v;
    }
    return unless %need;

    unless ($db) {
        my $u = LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_master($u) :  LJ::get_cluster_reader($u);
        return unless $db;
    }

    LJ::load_props("talk");
    my $in = join(',', keys %need);
    my $sth = $db->prepare("SELECT jtalkid, tpropid, value FROM talkprop2 ".
                           "WHERE journalid=? AND jtalkid IN ($in)");
    $sth->execute($userid);
    while (my ($jtalkid, $propid, $value) = $sth->fetchrow_array) {
        my $p = $LJ::CACHE_PROPID{'talk'}->{$propid};
        next unless $p;
        $hashref->{$jtalkid}->{$p->{'name'}} = $value;
    }
    foreach my $id (keys %need) {
        LJ::MemCache::set([$userid,"talkprop:$userid:$id"], $hashref->{$id} || {});
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
*eall = \&ehtml;  # old BML syntax required eall to also escape BML.  not anymore.

# <LJFUNC>
# name: LJ::ejs
# class: text
# des: Escapes a string value before it can be put in JavaScript.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub ejs
{
    my $a = $_[0];
    $a =~ s/[\"\'\\]/\\$&/g;
    $a =~ s/\r?\n/\\n/gs;
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

sub day_of_week
{
    my ($year, $month, $day) = @_;
    my $time = Time::Local::timelocal(0,0,0,$day,$month-1,$year);
    return (localtime($time))[6];
}

# <LJFUNC>
# name: LJ::delete_item2
# des: Deletes a user's journal item from a cluster.
# args: dbcm, journalid, jitemid, quick?, anum?
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
    my ($dbcm, $jid, $jitemid, $quick, $anum) = @_;
    $jid += 0; $jitemid += 0;

    my $and;
    if (defined $anum) { $and = "AND anum=" . ($anum+0); }
    my $dc = $dbcm->do("DELETE FROM log2 WHERE journalid=$jid AND jitemid=$jitemid $and");
    return 1 if $dc < 1;  # already deleted?

    return LJ::cmd_buffer_add($dbcm, $jid, "delitem", {
        'itemid' => $jitemid,
        'anum' => $anum,
    }) if $quick;

    # delete from clusters
    foreach my $t (qw(logtext2 logprop2 logsec2)) {
        $dbcm->do("DELETE FROM $t WHERE journalid=$jid AND jitemid=$jitemid");
    }
    LJ::dudata_set($dbcm, $jid, 'L', $jitemid, 0);

    # delete stuff from meta cluster
    my $aitemid = $jitemid * 256 + $anum;
    my $dbh = LJ::get_db_writer();
    foreach my $t (qw(memorable)) {
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
        LJ::delete_talkitem($dbcm, $jid, $t);
        $loop = 0 unless @$t == 50;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::delete_talkitem
# des: Deletes a comment (or multiple) and associated metadata.
# info: The tables [dbtable[talk2]], [dbtable[talkprop2]], [dbtable[talktext2]],
#       and [dbtable[dudata]] are all
#       deleted from, immediately. Unlike [func[LJ::delete_item2]], there is
#       no $quick flag to queue the delete for later, nor is one really
#       necessary, since deleting from 4 tables won't be too slow.
# args: dbcm, journalid, jtalkid, light?
# des-journalid: Journalid (userid from [dbtable[user]] to delete comment from).
#                The journal must reside on the $dbcm you provide.
# des-jtalkid: The jtalkid of the comment.  Or, an arrayref of jtalkids to delete multiple
# des-dbcm: Cluster master db to delete item from.
# des-light: boolean; if true, only mark entry as deleted, so children will thread.
# returns: boolean; number of items deleted on success (or zero-but-true), 0 on failure.
# </LJFUNC>
sub delete_talkitem
{
    my ($dbcm, $jid, $jtalkid, $light) = @_;
    $jid += 0;
    $jtalkid = [ $jtalkid ] unless ref $jtalkid eq "ARRAY";

    my $in = join(',', map { $_+0 } @$jtalkid);
    return 1 unless $in;
    my $where = "WHERE journalid=$jid AND jtalkid IN ($in)";

    my $ret;
    my @delfrom = qw(talkprop2);
    if ($light) {
        $ret = $dbcm->do("UPDATE talk2 SET state='D' $where");
        $dbcm->do("UPDATE talktext2 SET subject=NULL, body=NULL $where");
    } else {
        push @delfrom, qw(talk2 talktext2);
    }

    foreach my $t (@delfrom) {
        my $num = $dbcm->do("DELETE FROM $t $where");
        if (! defined $ret && $t eq "talk2") { $ret = $num; }
        return 0 if $dbcm->err;
    }
    
    return 0 if $dbcm->err;
    return $ret;
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
# args: userida, useridb, opts?
# des-userida: Userid of source user (befriender)
# des-useridb: Userid of target user (befriendee)
# des-opts: hashref; 'defaultview' key means add $useridb to $userida's Default View friends group
# returns: boolean; 1 on success (or already friend), 0 on failure (bogus args)
# </LJFUNC>
sub add_friend
{
    &nodb;    
    my ($ida, $idb, $opts) = @_;

    $ida += 0; $idb += 0; 
    return 0 unless $ida and $idb;
    
    my $dbh = LJ::get_db_writer();

    my $black = LJ::color_todb("#000000");
    my $white = LJ::color_todb("#ffffff");

    my $groupmask = 1;
    if ($opts->{'defaultview'}) {
        my $grp = $dbh->selectrow_array("SELECT groupnum FROM friendgroup WHERE userid=? AND groupname='Default View'", undef, $ida);
        $groupmask |= (1 << $grp) if $grp;
    }

    $dbh->do("INSERT INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) ".
             "VALUES ($ida, $idb, $black, $white, $groupmask)");

    return 1;
}

# <LJFUNC>
# name: LJ::event_register
# des: Logs a subscribable event, if anybody's subscribed to it.
# args: dbarg?, dbc, etype, ejid, eiarg, duserid, diarg
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
    &nodb;    
    my ($dbc, $etype, $ejid, $eiarg, $duserid, $diarg) = @_;
    my $dbr = LJ::get_db_reader();

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
# name: LJ::procnotify_add
# des: Sends a message to all other processes on all clusters.
# info: You'll probably never use this yourself.
# args: dbarg, cmd, args?
# des-cmd: Command name.  Currently recognized: "DBI::Role::reload" and "rename_user"
# des-args: Hashref with key/value arguments for the given command.  See
#           relevant parts of [func[LJ::procnotify_callback]] for required args for different commands.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_add
{
    my ($dbarg, $cmd, $argref) = @_;
    my $dbs = make_dbs_from_arg($dbarg);
    my $dbh = $dbs->{'dbh'};
    return 0 unless $dbh;

    my $args = join('&', map { LJ::eurl($_) . "=" . LJ::eurl($argref->{$_}) }
                    sort keys %$argref);
    $dbh->do("INSERT INTO procnotify (cmd, args) VALUES (?,?)",
             undef, $cmd, $args);
    return 0 if $dbh->err;
    return $dbh->{'mysql_insertid'};
}
# <LJFUNC>
# name: LJ::procnotify_callback
# des: Call back function process notifications.
# info: You'll probably never use this yourself.
# args: cmd, argstring
# des-cmd: Command name.
# des-argstring: String of arguments.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_callback
{
    my ($cmd, $argstring) = @_;
    my $arg = {};
    LJ::decode_url_string($argstring, $arg);
    
    if ($cmd eq "rename_user") {
        # this looks backwards, but the cache hash names are just odd:
        delete $LJ::CACHE_USERNAME{$arg->{'userid'}};
        delete $LJ::CACHE_USERID{$arg->{'user'}};
        return;
    }

    if ($cmd eq "ban_ip") {
        $LJ::IP_BANNED{$arg->{'ip'}} = 1;
        return;
    }

    if ($cmd eq "unban_ip") {
        delete $LJ::IP_BANNED{$arg->{'ip'}};
        return;
    }
}

sub procnotify_check
{
    my $now = time;
    return if $LJ::CACHE_PROCNOTIFY_CHECK + 30 > $now;
    $LJ::CACHE_PROCNOTIFY_CHECK = $now;
    
    my $dbr = LJ::get_db_reader();
    my $max = $dbr->selectrow_array("SELECT MAX(nid) FROM procnotify");
    return unless defined $max;
    my $old = $LJ::CACHE_PROCNOTIFY_MAX;
    if (defined $old && $max > $old) {
        my $sth = $dbr->prepare("SELECT cmd, args FROM procnotify ".
                                "WHERE nid > ? AND nid <= $max ORDER BY nid");
        $sth->execute($old);
        while (my ($cmd, $args) = $sth->fetchrow_array) {
            LJ::procnotify_callback($cmd, $args);
        }
    }
    $LJ::CACHE_PROCNOTIFY_MAX = $max;
}

sub dbtime_callback {
    my ($dsn, $dbtime, $time) = @_;
    my $diff = abs($dbtime - $time);
    if ($diff > 2) {
        $dsn =~ /host=([^:\;\|]*)/;
        my $db = $1;
        print STDERR "Clock skew of $diff seconds between web($LJ::SERVER_NAME) and db($db)\n";
    }
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

    if (LJ::are_hooks("is_utf8")) {
        return LJ::run_hook("is_utf8", $text);
    }

    # for a discussion of the different utf8 validity checking methods,
    # see:  http://zilla.livejournal.org/657
    # in summary, this isn't the fastest, but it's pretty fast, it doesn't make
    # perl segfault, and it doesn't add new crazy dependencies.  if you want
    # speed, check out ljcom's is_utf8 version in C, using Inline.pm

    my $u = Unicode::String::utf8($text);
    my $text2 = $u->utf8;
    return $text eq $text2;
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
    if (ref ($text) eq "ARRAY") {
        return ! (grep { !LJ::is_utf8($_) } @{$text});
    }
    return LJ::is_utf8($text);
}

# <LJFUNC>
# name: LJ::text_convert
# des: convert old entries/comments to UTF-8 using user's default encoding
# args: dbs?, text, u, error
# des-text: old possibly non-ASCII text to convert
# des-u: user hashref of the journal's owner
# des-error: ref to a scalar variable which is set to 1 on error 
#            (when user has no default encoding defined, but 
#            text needs to be translated)
# returns: converted text or undef on error
# </LJFUNC>
sub text_convert
{
    &nodb;
    my ($text, $u, $error) = @_;

    # maybe it's pure ASCII?
    return $text if LJ::is_ascii($text);

    # load encoding id->name mapping if it's not loaded yet
    LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
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
# name: LJ::text_length
# des: returns both byte length and character length of a string. In a non-Unicode
#      environment, this means byte length twice. In a Unicode environment,
#      the function assumes that its argument is a valid UTF-8 string.
# args: text
# des-text: the string to measure
# returns: a list of two values, (byte_length, char_length).
# </LJFUNC>

sub text_length 
{
    my $text = shift;
    my $bl = length($text);
    unless ($LJ::UNICODE) {
        return ($bl, $bl);
    }
    my $cl = 0;
    my $utf_char = "([\x00-\x7f]|[\xc0-\xdf].|[\xe0-\xef]..|[\xf0-\xf7]...)";

    while ($text =~ m/$utf_char/go) { $cl++; }
    return ($bl, $cl);
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
# </LJFUNC>
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
# args: dbs?, u, subject, text, props
# des-u: user hashref of the journal's owner
# des-subject: ref to the item's subject
# des-text: ref to the item's text
# des-props: hashref of the item's props
# returns: nothing.
# </LJFUNC>
sub item_toutf8
{
    shift if ref $_[0] eq "LJ::DBSet";
    my ($u, $subject, $text, $props) = @_;
    return unless $LJ::UNICODE;

    my $convert = sub {
        my $rtext = shift;
        my $error = 0;
        my $res = LJ::text_convert($$rtext, $u, \$error);
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

# <LJFUNC>
# name: LJ::set_interests
# des: Change a user's interests
# args: dbarg?, userid, old, new
# arg-old: hashref of old interests (hasing being interest => intid)
# arg-new: listref of new interests
# returns: 1
# </LJFUNC>
sub set_interests
{
    &nodb;    

    my ($userid, $old, $new) = @_;

    my $dbh = LJ::get_db_writer();
    my %int_new = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    foreach my $int (@$new)
    {
        $int = lc($int);       # FIXME: use utf8?
        $int =~ s/^i like //;  # *sigh*
        next unless $int;
        next if $int =~ / .+ .+ .+ /;  # prevent sentences
        next if $int =~ /[\<\>]/;
        my ($bl, $cl) = LJ::text_length($int);
        next if $bl > LJ::BMAX_INTEREST or $cl > LJ::CMAX_INTEREST;
        $int_new{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### were interests removed?
    if (%int_del)
    {
        ## easy, we know their IDs, so delete them en masse
        my $intid_in = join(", ", values %int_del);
        $dbh->do("DELETE FROM userinterests WHERE userid=$userid AND intid IN ($intid_in)");
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)");
    }

    ### do we have new interests to add?
    if (%int_new)
    {
        ## difficult, have to find intids of interests, and create new ints for interests
        ## that nobody has ever entered before
        my $int_in = join(", ", map { $dbh->quote($_); } keys %int_new);
        my %int_exist;
        my @new_intids = ();  ## existing IDs we'll add for this user

        ## find existing IDs
        my $sth = $dbh->prepare("SELECT interest, intid FROM interests WHERE interest IN ($int_in)");
        $sth->execute;
        while (my ($intr, $intid) = $sth->fetchrow_array) {
            push @new_intids, $intid;       # - we'll add this later.
            delete $int_new{$intr};         # - so we don't have to make a new intid for
                                            #   this next pass.
        }

        if (@new_intids) {
            my $sql = "";
            foreach my $newid (@new_intids) {
                if ($sql) { $sql .= ", "; }
                else { $sql = "REPLACE INTO userinterests (userid, intid) VALUES "; }
                $sql .= "($userid, $newid)";
            }
            $dbh->do($sql);

            my $intid_in = join(", ", @new_intids);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    ### do we STILL have interests to add?  (must make new intids)
    if (%int_new)
    {
        foreach my $int (keys %int_new)
        {
            my $intid;
            my $qint = $dbh->quote($int);

            $dbh->do("INSERT INTO interests (intid, intcount, interest) ".
                     "VALUES (NULL, 1, $qint)");
            if ($dbh->err) {
                # somebody beat us to creating it.  find its id.
                $intid = $dbh->selectrow_array("SELECT intid FROM interests WHERE interest=$qint");
                $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid=$intid");
            } else {
                # newly created
                $intid = $dbh->{'mysql_insertid'};
            }
            if ($intid) {
                ## now we can actually insert it into the userinterests table:
                $dbh->do("INSERT INTO userinterests (userid, intid) ".
                         "VALUES ($userid, $intid)");
            }
        }
    }
    return 1;
}

# returns 1 if action is permitted.  0 if above rate or fail.
# action isn't logged on fail.
#
# opts keys:
#   -- "limit_by_ip" => "1.2.3.4"  (when used for checking rate)
#   -- 
sub rate_log
{
    my ($u, $ratename, $count, $opts) = @_;
    my $rateperiod = LJ::get_cap($u, "rateperiod-$ratename");
    return 1 unless $rateperiod;

    my $dbu = LJ::get_cluster_master($u);
    return 0 unless $dbu;
    
    my $rp = LJ::get_prop("rate", $ratename);
    return 0 unless $rp;
    
    my $now = time();
    my $beforeperiod = $now - $rateperiod;
    
    # delete inapplicable stuff (or some of it)
    $dbu->do("DELETE FROM ratelog WHERE userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
             "AND evttime < $beforeperiod LIMIT 1000");
    
    # check rate.  (okay per period)
    my $opp = LJ::get_cap($u, "rateallowed-$ratename");
    return 1 unless $opp;
    my $udbr = LJ::get_cluster_reader($u);
    my $ip = $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    my $sum = $udbr->selectrow_array("SELECT COUNT(quantity) FROM ratelog WHERE ".
                                     "userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
                                     "AND ip=INET_ATON($ip) ".
                                     "AND evttime > $beforeperiod");

    # would this transaction go over the limit?
    if ($sum + $count > $opp) {
        # TODO: optionally log to rateabuse, unless caller is doing it themselves
        # somehow, like with the "loginstall" table.
        return 0;
    }

    # log current
    $count = $count + 0;
    $dbu->do("INSERT INTO ratelog (userid, rlid, evttime, ip, quantity) VALUES ".
             "($u->{'userid'}, $rp->{'id'}, $now, INET_ATON($ip), $count)");
    return 1;
}

# We're not always running under mod_perl... sometimes scripts (syndication sucker)
# call paths which end up thinking they need the remote IP, but don't.
sub get_remote_ip
{
    my $ip;
    eval {
        $ip = Apache->request->connection->remote_ip;
    };
    return $ip || $ENV{'FAKE_IP'} || $ENV{'REMOTE_ADDR'};
}

sub login_ip_banned
{
    my $u = shift;
    return 0 unless $u;

    my $ip;
    return 0 unless ($ip = LJ::get_remote_ip());

    my $udbr;
    my $rateperiod = LJ::get_cap($u, "rateperiod-failed_login");
    if ($rateperiod && ($udbr = LJ::get_cluster_reader($u))) {
        my $bantime = $udbr->selectrow_array("SELECT time FROM loginstall WHERE ".
                                             "userid=$u->{'userid'} AND ip=INET_ATON(?)",
                                             undef, $ip);
        if ($bantime && $bantime > time() - $rateperiod) {
            return 1;
        }
    }
    return 0;
}

sub handle_bad_login
{
    my $u = shift;
    return 1 unless $u;

    my $ip;
    return 1 unless ($ip = LJ::get_remote_ip());
    # an IP address is permitted such a rate of failures
    # until it's banned for a period of time.
    my $udbh;
    if (! LJ::rate_log($u, "failed_login", 1, { 'limit_by_ip' => $ip }) &&
        ($udbh = LJ::get_cluster_master($u)))
    {
        $udbh->do("REPLACE INTO loginstall (userid, ip, time) VALUES ".
                  "(?,INET_ATON(?),UNIX_TIMESTAMP())", undef, $u->{'userid'}, $ip);
    }
    return 1;
}

sub md5_struct
{
    my ($st, $md5) = @_;
    $md5 ||= Digest::MD5->new;
    unless (ref $st) {
        if ($] < 5.007 && $Digest::MD5::VERSION > 2.13) {
            # remove the Sv_UTF8 flag from the scalar, otherwise
            # stupid later Digest::MD5s crash while trying to work-
            # around what they think is perl 5.6's lack of utf-8 
            # support, even though it's not totally necessary
            # see http://zilla.livejournal.org/show_bug.cgi?id=851
            $st = pack('C*', unpack('C*', $st));
        }
        $md5->add($st);
        return $md5;
    }
    if (ref $st eq "HASH") {
        foreach (sort keys %$st) {
            md5_struct($_, $md5);
            md5_struct($st->{$_}, $md5);           
        }
        return $md5;
    }
    if (ref $st eq "ARRAY") {
        foreach (@$st) {
            md5_struct($_, $md5);
        }
        return $md5;
    }
}

sub rand_chars
{
    my $length = shift;
    my $chal = "";
    my $digits = "abcdefghijklmnopqrstuvwzyzABCDEFGHIJKLMNOPQRSTUVWZYZ0123456789";
    for (1..$length) {
        $chal .= substr($digits, int(rand(62)), 1);
    }
    return $chal;
}

sub generate_session
{
    my ($u, $opts) = @_;
    my $udbh = LJ::get_cluster_master($u);
    my $sess = {};
    $opts->{'exptype'} = "short" unless $opts->{'exptype'} eq "long";
    $sess->{'auth'} = LJ::rand_chars(10);
    my $expsec = $opts->{'exptype'} eq "short" ? 60*60*24 : 60*60*24*7;
    $udbh->do("INSERT INTO sessions (userid, sessid, auth, exptype, ".
              "timecreate, timeexpire, ipfixed) VALUES (?,NULL,?,?,UNIX_TIMESTAMP(),".
              "UNIX_TIMESTAMP()+$expsec,?)", undef,
              $u->{'userid'}, $sess->{'auth'}, $opts->{'exptype'}, $opts->{'ipfixed'});
    return undef if $udbh->err;
    $sess->{'sessid'} = $udbh->{'mysql_insertid'};
    $sess->{'userid'} = $u->{'userid'};
    $sess->{'ipfixed'} = $opts->{'ipfixed'};
    $sess->{'exptype'} = $opts->{'exptype'};

    # clean up old sessions
    my $old = $udbh->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
                                        "userid=$u->{'userid'} AND ".
                                        "timeexpire < UNIX_TIMESTAMP()");
    LJ::kill_sessions($udbh, $u->{'userid'}, @$old) if $old;

    # mark account as being used
    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE userusage SET timecheck=NOW() WHERE userid=?",
             undef, $u->{'userid'});

    return $sess;
}

sub kill_all_sessions
{
    my $u = shift;
    return 0 unless $u;
    my $udbs = LJ::get_cluster_set($u);
    my $udbh = $udbs->{'dbh'};
    my $udbr = $udbs->{'reader'};

    my $sessions = $udbr->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
					     "userid=$u->{'userid'}");
    LJ::kill_sessions($udbh, $u->{'userid'}, @$sessions) if @$sessions;
}

sub kill_sessions
{
    my ($udbh, $userid, @sessids) = @_;
    my $in = join(',', map { $_+0 } @sessids);
    return 1 unless $in;
    foreach (qw(sessions sessions_data)) {
        $udbh->do("DELETE FROM $_ WHERE userid=? AND ".
                  "sessid IN ($in)", undef, $userid);
    }
    foreach my $id (@sessids) {
        $id += 0;
        my $memkey = [$userid,"sess:$userid:$id"];
        LJ::MemCache::delete($memkey);
    }
    return 1;
}

sub kill_session
{
    my $u = shift;
    return 0 unless $u;
    return 0 unless exists $u->{'_session'};
    my $udbh = LJ::get_cluster_master($u);
    LJ::kill_sessions($udbh, $u->{'userid'}, $u->{'_session'}->{'sessid'});
    delete $BML::COOKIE{'ljsession'};
    return 1;
}

# <LJFUNC>
# name: LJ::load_rel_user
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'userid' participates on the left side (is the source of the
#      relationship).
# args: dbarg?, userid, type
# arg-userid: userid or a user hash to load relationship information for.
# arg-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_user
{
    my $dbarg = (ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db") ? shift : undef;
    my ($userid, $type) = @_;
    return undef unless $type and $userid;
    $userid = LJ::want_userid($userid);
    my $dbr;
    $dbr = $dbarg->{'reader'} if ref $dbarg eq "LJ::DBSet";
    $dbr ||= $dbarg || LJ::get_db_reader();
    return $dbr->selectcol_arrayref("SELECT targetid FROM reluser WHERE userid=? AND type=?",
                                    undef, $userid, $type);
}

# <LJFUNC>
# name: LJ::load_rel_target
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'targetid' participates on the right side (is the target of the
#      relationship).
# args: dbarg?, targetid, type
# arg-targetid: userid or a user hash to load relationship information for.
# arg-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_target
{
    my $dbarg = (ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db") ? shift : undef;
    my ($targetid, $type) = @_;
    return undef unless $type and $targetid;
    $targetid = LJ::want_userid($targetid);
    my $dbr;
    $dbr = $dbarg->{'reader'} if ref $dbarg eq "LJ::DBSet";
    $dbr ||= $dbarg || LJ::get_db_reader();
    return $dbr->selectcol_arrayref("SELECT userid FROM reluser WHERE targetid=? AND type=?",
                                    undef, $targetid, $type);
}

# <LJFUNC>
# name: LJ::check_rel
# des: Checks whether two users are in a specified relationship to each other.
# args: dbarg?, userid, targetid, type
# arg-userid: source userid, nonzero; may also be a user hash.
# arg-targetid: target userid, nonzero; may also be a user hash.
# arg-type: type of the relationship
# returns: 1 if the relationship exists, 0 otherwise
# </LJFUNC>
sub check_rel
{
    my $dbarg;
    $dbarg = shift @_ if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db";
    my ($userid, $targetid, $type) = @_;
    return undef unless $type and $userid and $targetid;
    $userid = LJ::want_userid($userid); 
    $targetid = LJ::want_userid($targetid);

    my $key = "$userid-$targetid-$type";
    return $LJ::REQ_CACHE_REL{$key} if defined $LJ::REQ_CACHE_REL{$key};

    my $dbs = LJ::make_dbs_from_arg($dbarg || LJ::get_db_reader());
    my $dbh = $dbs->{'dbh'};
    my $qtype = $dbh->quote($type);

    my $sql = "SELECT COUNT(*) FROM reluser WHERE userid=$userid AND type=$qtype AND targetid=$targetid";
    my $res = LJ::dbs_selectrow_array($dbs, $sql);
    return $LJ::REQ_CACHE_REL{$key} = ($res ? 1 : 0);
}

# <LJFUNC>
# name: LJ::set_rel
# des: Sets relationship information for two users.
# args: dbs?, userid, targetid, type
# arg-userid: source userid, or a user hash
# arg-targetid: target userid, or a user hash
# arg-type: type of the relationship
# </LJFUNC>
sub set_rel 
{
    &nodb;
    my ($userid, $targetid, $type) = @_;
    return undef unless $type and $userid and $targetid;
    $userid = LJ::want_userid($userid);
    $targetid = LJ::want_userid($targetid);

    my $dbh = LJ::get_db_writer();
    my $qtype = $dbh->quote($type);
    my $sql = "REPLACE INTO reluser (userid,targetid,type) VALUES ($userid,$targetid,$qtype)";
    $dbh->do($sql);
    return;
}

# <LJFUNC>
# name: LJ::clear_rel
# des: Deletes a relationship between two users or all relationships of a particular type
#      for one user, on either side of the relationship. One of userid,targetid -- bit not
#      both -- may be '*'. In that case, if, say, userid is '*', then all relationship 
#      edges with target equal to targetid and of the specified type are deleted. 
#      If both userid and targetid are numbers, just one edge is deleted.
# args: dbs?, userid, targetid, type
# arg-userid: source userid, or a user hash, or '*'
# arg-targetid: target userid, or a user hash, or '*'
# arg-type: type of the relationship
# </LJFUNC>
sub clear_rel 
{
    &nodb;
    my ($userid, $targetid, $type) = @_;
    return undef unless $type and $userid or $targetid;
    return undef if $userid eq '*' and $targetid eq '*';

    $userid = LJ::want_userid($userid) unless $userid eq '*';
    $targetid = LJ::want_userid($targetid) unless $targetid eq '*';

    my $dbh = LJ::get_db_writer();
    my $qtype = $dbh->quote($type);
    my $sql = "DELETE FROM reluser WHERE " . ($userid ne '*' ? "userid=$userid AND " : "") .
              ($targetid ne '*' ? "targetid=$targetid AND " : "") . "type=$qtype";
    $dbh->do($sql);
    return;
}

# $dom: 'L' == log, 'T' == talk, 'M' == modlog
sub alloc_user_counter
{
    my ($u, $dom, $pre_locked) = @_;
    return undef unless $dom =~ /^[LTM]$/;
    my $dbcm = LJ::get_cluster_master($u);
    return undef unless $dbcm;

    my $uid = $u->{'userid'}+0;
    my $key = "usercounter-$uid-$dom";
    unless ($pre_locked) {
        my $r = $dbcm->selectrow_array("SELECT GET_LOCK(?, 3)", undef, $key);
        return undef unless $r;
    }
    my $newmax;

    my $rs = $dbcm->do("UPDATE counter SET max=max+1 WHERE journalid=? AND area=?",
                       undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbcm->selectrow_array("SELECT max FROM counter WHERE journalid=? AND area=?",
                                         undef, $uid, $dom);
    } else {
        if ($dom eq "L") {
            $newmax = $dbcm->selectrow_array("SELECT MAX(jitemid) FROM log2 WHERE journalid=?",
                                            undef, $uid);
        } elsif ($dom eq "T") {
            $newmax = $dbcm->selectrow_array("SELECT MAX(jtalkid) FROM talk2 WHERE journalid=?",
                                            undef, $uid);
        } elsif ($dom eq "M") {
            $newmax = $dbcm->selectrow_array("SELECT MAX(modid) FROM modlog WHERE journalid=?",
                                            undef, $uid);
        }
        $newmax++;
        $dbcm->do("INSERT INTO counter (journalid, area, max) VALUES (?,?,?)",
                  undef, $uid, $dom, $newmax) or return undef;
    }

    unless ($pre_locked) {
        $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $key);
    }
    
    return $newmax;
}

# given a unix time, returns;
#   ($week, $ubefore)
# week: week number (week 0 is first 3 days of unix time)
# ubefore:  seconds before the next sunday, divided by 10
sub weekuu_parts {
    my $time = shift;
    $time -= 86400*3;  # time from the sunday after unixtime 0
    my $WEEKSEC = 86400*7;
    my $week = int(($time+$WEEKSEC) / $WEEKSEC);
    my $uafter = int(($time % $WEEKSEC) / 10);
    my $ubefore = int(60480 - ($time % $WEEKSEC) / 10);
    return ($week, $uafter, $ubefore);
}

sub weekuu_before_to_time
{
    my ($week, $ubefore) = @_;
    my $WEEKSEC = 86400*7;
    my $time = $week * $WEEKSEC + 86400*3;
    $time -= 10 * $ubefore;
    return $time;
}

sub weekuu_after_to_time
{
    my ($week, $uafter) = @_;
    my $WEEKSEC = 86400*7;
    my $time = ($week-1) * $WEEKSEC + 86400*3;
    $time += 10 * $uafter;
    return $time;
}

sub paging_bar
{
    my ($page, $pages) = @_;
    
    my $navcrap;
    if ($pages > 1) {
        $navcrap .= "<center><font face='Arial,Helvetica' size='-1'><b>";
        $navcrap .= BML::ml('ljlib.pageofpages',{'page'=>$page, 'total'=>$pages}) . "<br />";
        my $left = "<b>&lt;&lt;</b>";
        if ($page > 1) { $left = "<a href='" . BML::self_link({ 'page' => $page-1 }) . "'>$left</a>"; }
        my $right = "<b>&gt;&gt;</b>";
        if ($page < $pages) { $right = "<a href='" . BML::self_link({ 'page' => $page+1 }) . "'>$right</a>"; }
        $navcrap .= $left . " ";
        for (my $i=1; $i<=$pages; $i++) {
            my $link = "[$i]";
            if ($i != $page) { $link = "<a href='" . BML::self_link({ 'page' => $i }) . "'>$link</a>"; }
            else { $link = "<font size='+1'><b>$link</b></font>"; }
            $navcrap .= "$link ";
        }
        $navcrap .= "$right";
        $navcrap .= "</font></center>\n";
        $navcrap = BML::fill_template("standout", { 'DATA' => $navcrap });
    }
    return $navcrap;
}

sub make_login_session
{
    my ($u, $exptype, $ipfixed) = @_;
    $exptype ||= 'short';
    return 0 unless $u;

    my $etime = 0;
    eval { Apache->request->notes('ljuser' => $u->{'user'}); };

    my $sess_opts = {
        'exptype' => $exptype,
        'ipfixed' => $ipfixed,
    };
    my $sess = LJ::generate_session($u, $sess_opts);
    $BML::COOKIE{'ljsession'} = [  "ws:$u->{'user'}:$sess->{'sessid'}:$sess->{'auth'}", $etime, 1 ];
    LJ::set_remote($u);

    LJ::load_user_props($u, "browselang", "schemepref" );
    my $bl = LJ::Lang::get_lang($u->{'browselang'});
    if ($bl) {
        BML::set_cookie("langpref", $bl->{'lncode'} . "/" . time(), 0, $LJ::COOKIE_PATH, $LJ::COOKIE_DOMAIN);
        BML::set_language($bl->{'lncode'});
    }
    
    # restore default scheme
    if ($u->{'schemepref'} ne "") {
      BML::set_cookie("BMLschemepref", $u->{'schemepref'}, 0, $LJ::COOKIE_PATH, $LJ::COOKIE_DOMAIN);
      BML::set_scheme($u->{'schemepref'});
    }
    
    LJ::run_hooks("post_login", {
        "u" => $u,
        "form" => {},
        "expiretime" => $etime,
    });

    return 1;
}

sub last_error_code
{
    return $LJ::last_error;
}

sub last_error
{
    my $err = {
        'utf8' => "Encoding isn't valid UTF-8",
        'db' => "Database error",
    };
    my $des = $err->{$LJ::last_error};
    if ($LJ::last_error eq "db" && $LJ::db_error) {
        $des .= ": $LJ::db_error";
    }
    return $des || $LJ::last_error;
}

sub error
{
    my $err = shift;
    if (ref $err eq "DBI::db") {
        $LJ::db_error = $err->errstr;
        $err = "db";
    } elsif ($err eq "db") {
        $LJ::db_error = "";
    }
    $LJ::last_error = $err;
    return undef;
}

# to be called as &nodb; (so this function sees caller's @_)
sub nodb { shift @_ if ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db"; }

1;
