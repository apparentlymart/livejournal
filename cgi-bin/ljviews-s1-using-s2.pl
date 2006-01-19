#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/ljlib.pl, cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/cleanhtml.pl
# </LJDEP>

use strict;

package LJ::S1;

use vars qw(@themecoltypes);

# this used to be in a table, but that was kinda useless
@themecoltypes = (
                  [ 'page_back', 'Page background' ],
                  [ 'page_text', 'Page text' ],
                  [ 'page_link', 'Page link' ],
                  [ 'page_vlink', 'Page visited link' ],
                  [ 'page_alink', 'Page active link' ],
                  [ 'page_text_em', 'Page emphasized text' ],
                  [ 'page_text_title', 'Page title' ],
                  [ 'weak_back', 'Weak accent' ],
                  [ 'weak_text', 'Text on weak accent' ],
                  [ 'strong_back', 'Strong accent' ],
                  [ 'strong_text', 'Text on strong accent' ],
                  [ 'stronger_back', 'Stronger accent' ],
                  [ 'stronger_text', 'Text on stronger accent' ],
                  );

# updated everytime new S1 style cleaning rules are added,
# so cached cleaned versions are invalidated.
$LJ::S1::CLEANER_VERSION = 5;

# PROPERTY Flags:

# /a/:
#    safe in styles as sole attributes, without any cleaning.  for
#    example: <a href="%%urlread%%"> is okay, # if we're in
#    LASTN_TALK_READLINK, because the system generates # %%urlread%%.
#    by default, if we don't declare things trusted here, # we'll
#    double-check all attributes at the end for potential XSS #
#    problems.
#
# /u/:
#    is a URL.  implies /a/.
#
#
# /d/:
#    is a number.  implies /a/.
#
# /t/:
#    tainted!  User controls via other some other variable.
#
# /s/:
#    some system string... probably safe.  but maybe possible to coerce it
#    alongside something else.

my $commonprop = {
    'dateformat' => {
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'min' => 'd',
        '12h' => 'd', '12hh' => 'd',
        '24h' => 'd', '24hh' => 'd',
    },
    'talklinks' => {
        'messagecount' => 'd',
        'urlread' => 'u',
        'urlpost' => 'u',
        'itemid' => 'd',
    },
    'talkreadlink' => {
        'messagecount' => 'd',
        'urlread' => 'u',
    },
    'event' => {
        'itemid' => 'd',
    },
    'pic' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },
    'newday' => {
        yy => 'd', yyyy => 'd', m => 'd', mm => 'd',
        d => 'd', dd => 'd',
    },
    'skip' => {
        'numitems' => 'd',
        'url' => 'u',
    },

};

$LJ::S1::PROPS = {
    'CALENDAR_DAY' => {
        'd' => 'd',
        'eventcount' => 'd',
        'dayevent' => 't',
        'daynoevent' => 't',
    },
    'CALENDAR_DAY_EVENT' => {
        'eventcount' => 'd',
        'dayurl' => 'u',
    },
    'CALENDAR_DAY_NOEVENT' => {
    },
    'CALENDAR_EMPTY_DAYS' => {
        'numempty' => 'd',
    },
    'CALENDAR_MONTH' => {
        'monlong' => 's',
        'monshort' => 's',
        'yy' => 'd',
        'yyyy' => 'd',
        'weeks' => 't',
        'urlmonthview' => 'u',
    },
    'CALENDAR_NEW_YEAR' => {
        'yy' => 'd',
        'yyyy' => 'd',
    },
    'CALENDAR_PAGE' => {
        'name' => 't',
        "name-'s" => 's',
        'yearlinks' => 't',
        'months' => 't',
        'username' => 's',
        'website' => 't',
        'head' => 't',
        'urlfriends' => 'u',
        'urllastn' => 'u',
    },
    'CALENDAR_WEBSITE' => {
        'url' => 't',
        'name' => 't',
    },
    'CALENDAR_WEEK' => {
        'days' => 't',
        'emptydays_beg' => 't',
        'emptydays_end' => 't',
    },
    'CALENDAR_YEAR_DISPLAYED' => {
        'yyyy' => 'd',
        'yy' => 'd',
    },
    'CALENDAR_YEAR_LINK' => {
        'yyyy' => 'd',
        'yy' => 'd',
        'url' => 'u',
    },
    'CALENDAR_YEAR_LINKS' => {
        'years' => 't',
    },

    # day
    'DAY_DATE_FORMAT' => $commonprop->{'dateformat'},
    'DAY_EVENT' => $commonprop->{'event'},
    'DAY_EVENT_PRIVATE' => $commonprop->{'event'},
    'DAY_EVENT_PROTECTED' => $commonprop->{'event'},
    'DAY_PAGE' => {
        'prevday_url' => 'u',
        'nextday_url' => 'u',
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'urllastn' => 'u',
        'urlcalendar' => 'u',
        'urlfriends' => 'u',
    },
    'DAY_TALK_LINKS' => $commonprop->{'talklinks'},
    'DAY_TALK_READLINK' => $commonprop->{'talkreadlink'},

    # friends
    'FRIENDS_DATE_FORMAT' => $commonprop->{'dateformat'},
    'FRIENDS_EVENT' => $commonprop->{'event'},
    'FRIENDS_EVENT_PRIVATE' => $commonprop->{'event'},
    'FRIENDS_EVENT_PROTECTED' => $commonprop->{'event'},
    'FRIENDS_FRIENDPIC' => $commonprop->{'pic'},
    'FRIENDS_NEW_DAY' => $commonprop->{'newday'},
    'FRIENDS_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'FRIENDS_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'FRIENDS_SKIP_BACKWARD' => $commonprop->{'skip'},
    'FRIENDS_SKIP_FORWARD' => $commonprop->{'skip'},
    'FRIENDS_TALK_LINKS' => $commonprop->{'talklinks'},
    'FRIENDS_TALK_READLINK' => $commonprop->{'talkreadlink'},

    # lastn
    'LASTN_ALTPOSTER' => {
        'poster' => 's',
        'owner' => 's',
        'pic' => 't',
    },
    'LASTN_ALTPOSTER_PIC' => $commonprop->{'pic'},
    'LASTN_CURRENT' => {
        'what' => 's',
        'value' => 't',
    },
    'LASTN_CURRENTS' => {
        'currents' => 't',
    },
    'LASTN_DATEFORMAT' => $commonprop->{'dateformat'},
    'LASTN_EVENT' => $commonprop->{'event'},
    'LASTN_EVENT_PRIVATE' => $commonprop->{'event'},
    'LASTN_EVENT_PROTECTED' => $commonprop->{'event'},
    'LASTN_NEW_DAY' => $commonprop->{'newday'},
    'LASTN_PAGE' => {
        'urlfriends' => 'u',
        'urlcalendar' => 'u',
    },
    'LASTN_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'LASTN_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'LASTN_SKIP_BACKWARD' => $commonprop->{'skip'},
    'LASTN_SKIP_FORWARD' => $commonprop->{'skip'},
    'LASTN_TALK_LINKS' => $commonprop->{'talklinks'},
    'LASTN_TALK_READLINK' => $commonprop->{'talkreadlink'},
    'LASTN_USERPIC' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },

};

sub get_public_styles {

    my $opts = shift;

    # Try memcache if no extra options are requested
    my $memkey = "s1pubstyc";
    my $pubstyc = {};
    unless ($opts) {
        my $pubstyc = LJ::MemCache::get($memkey);
        return $pubstyc if $pubstyc;
    }

    # not cached, build from db
    my $sysid = LJ::get_userid("system");

    # all cols *except* formatdata, which is big and unnecessary for most uses.
    # it'll be loaded by LJ::S1::get_style
    my $cols = "styleid, styledes, type, is_public, is_embedded, ".
        "is_colorfree, opt_cache, has_ads, lastupdate";
    $cols .= ", formatdata" if $opts->{'formatdata'};

    # first try new table
    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare("SELECT userid, $cols FROM s1style WHERE userid=? AND is_public='Y'");
    $sth->execute($sysid);
    $pubstyc->{$_->{'styleid'}} = $_ while $_ = $sth->fetchrow_hashref;

    # fall back to old table
    unless (%$pubstyc) {
        $sth = $dbh->prepare("SELECT user, $cols FROM style WHERE user='system' AND is_public='Y'");
        $sth->execute();
        $pubstyc->{$_->{'styleid'}} = $_ while $_ = $sth->fetchrow_hashref;
    }
    return undef unless %$pubstyc;

    # set in memcache
    unless ($opts) {
        my $expire = time() + 60*30; # 30 minutes
        LJ::MemCache::set($memkey, $pubstyc, $expire);
    }

    return $pubstyc;
}

# <LJFUNC>
# name: LJ::S1::get_themeid
# des: Loads or returns cached version of given color theme data.
# returns: Hashref with color names as keys
# args: dbarg?, themeid
# des-themeid: S1 themeid.
# </LJFUNC>
sub get_themeid
{
    &LJ::nodb;
    my $themeid = shift;
    return $LJ::S1::CACHE_THEMEID{$themeid} if $LJ::S1::CACHE_THEMEID{$themeid};
    my $dbr = LJ::get_db_reader();
    my $ret = {};
    my $sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=?");
    $sth->execute($themeid);
    $ret->{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
    return $LJ::S1::CACHE_THEMEID{$themeid} = $ret;
}

# returns: hashref of vars (cleaned)
sub load_style
{
    &LJ::nodb;
    my ($styleid, $viewref) = @_;

    # first try local cache for this process
    my $cch = $LJ::S1::CACHE_STYLE{$styleid};
    if ($cch && $cch->{'cachetime'} > time() - 300) {
        $$viewref = $cch->{'type'} if ref $viewref eq "SCALAR";
        return $cch->{'style'};
    }

    # try memcache
    my $memkey = [$styleid, "s1styc:$styleid"];
    my $styc = LJ::MemCache::get($memkey);

    # database handle we'll use if we have to rebuild the cache
    my $db;

    # function to return a given a styleid
    my $find_db = sub {
        my $sid = shift;

        # should we work with a global or clustered table?
        my $userid = LJ::S1::get_style_userid($sid);

        # if the user's style is clustered, need to get a $u
        my $u = $userid ? LJ::load_userid($userid) : undef;

        # return appropriate db handle
        if ($u && $u->{'dversion'} >= 5) {    # users' styles are clustered
            return LJ::S1::get_s1style_writer($u);
        }

        return @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
    };

    # get database stylecache
    unless ($styc) {

        $db = $find_db->($styleid);
        $styc = $db->selectrow_hashref("SELECT * FROM s1stylecache WHERE styleid=?",
                                       undef, $styleid);
        LJ::MemCache::set($memkey, $styc, time()+60*30) if $styc;
    }

    # no stylecache in db, built a new one
    if (! $styc || $styc->{'vars_cleanver'} < $LJ::S1::CLEANER_VERSION) {
        my $style = LJ::S1::get_style($styleid);
        return {} unless $style;

        $db ||= $find_db->($styleid);

        $styc = {
            'type' => $style->{'type'},
            'opt_cache' => $style->{'opt_cache'},
            'vars_stor' => LJ::CleanHTML::clean_s1_style($style->{'formatdata'}),
            'vars_cleanver' => $LJ::S1::CLEANER_VERSION,
        };

        # do this query on the db handle we used above
        $db->do("REPLACE INTO s1stylecache (styleid, cleandate, type, opt_cache, vars_stor, vars_cleanver) ".
                "VALUES (?,NOW(),?,?,?,?)", undef, $styleid,
                map { $styc->{$_} } qw(type opt_cache vars_stor vars_cleanver));
    }

    my $ret = Storable::thaw($styc->{'vars_stor'});
    $$viewref = $styc->{'type'} if ref $viewref eq "SCALAR";

    if ($styc->{'opt_cache'} eq "Y") {
        $LJ::S1::CACHE_STYLE{$styleid} = {
            'style' => $ret,
            'cachetime' => time(),
            'type' => $styc->{'type'},
        };
    }

    return $ret;
}

# LJ::S1::get_public_styles
#
# LJ::load_user_props calls LJ::S1::get_public_styles and since
# a lot of cron jobs call LJ::load_user_props, we've moved
# LJ::S1::get_public_styles to ljlib so that it can be used
# without including ljviews.pl

sub get_s1style_writer {
    my $u = shift;
    return undef unless LJ::isu($u);

    # special case system, its styles live on
    # the global master's s1style table alone
    if ($u->{'user'} eq 'system') {
        return LJ::get_db_writer();
    }

    return $u->writer;
}

sub get_s1style_reader {
    my $u = shift;
    return undef unless LJ::isu($u);

    # special case system, its styles live on
    # the global master's s1style table alone
    if ($u->{'user'} eq 'system') {
        return @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
    }

    return @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
}

# takes either $u object or userid
sub get_user_styles {
    my $u = shift;
    $u = LJ::isu($u) ? $u : LJ::load_user($u);
    return undef unless $u;

    my %styles;

    # all cols *except* formatdata, which is big and unnecessary for most uses.
    # it'll be loaded by LJ::S1::get_style
    my $cols = "styleid, styledes, type, is_public, is_embedded, ".
        "is_colorfree, opt_cache, has_ads, lastupdate";

    # new clustered table
    my ($db, $sth);
    if ($u->{'dversion'} >= 5) {
        $db = LJ::S1::get_s1style_reader($u);
        $sth = $db->prepare("SELECT userid, $cols FROM s1style WHERE userid=?");
        $sth->execute($u->{'userid'});

    # old global table
    } else {
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $sth = $db->prepare("SELECT user, $cols FROM style WHERE user=?");
        $sth->execute($u->{'user'});
    }

    # build data structure
    while (my $row = $sth->fetchrow_hashref) {

        # fix up both userid and user values for consistency
        $row->{'userid'} = $u->{'userid'};
        $row->{'user'} = $u->{'user'};

        $styles{$row->{'styleid'}} = $row;
        next unless @LJ::MEMCACHE_SERVERS;

        # now update memcache while we have this data?
        LJ::MemCache::set([$row->{'styleid'}, "s1style:$row->{'styleid'}"], $row);
    }

    return \%styles;
}

# includes formatdata row.
sub get_style {
    my $styleid = shift;
    return unless $styleid;

    my $memkey = [$styleid, "s1style_all:$styleid"];
    my $style = LJ::MemCache::get($memkey);
    return $style if $style;

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        my $db = LJ::S1::get_s1style_reader($u);
        $style = $db->selectrow_hashref("SELECT * FROM s1style WHERE styleid=?", undef, $styleid);

        # fill in user since the caller may expect it
        $style->{'user'} = $u->{'user'};

    # old global table
    } else {
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $style = $db->selectrow_hashref("SELECT * FROM style WHERE styleid=?", undef, $styleid);

        # fill in userid since the caller may expect it
        $style->{'userid'} = LJ::get_userid($style->{'user'});
    }
    return unless $style;

    LJ::MemCache::set($memkey, $style);

    return $style;
}

sub check_dup_style {
    my ($u, $type, $styledes) = @_;
    return unless $type && $styledes;

    $u = LJ::isu($u) ? $u : LJ::load_user($u);

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        # get writer since this function is to check duplicates.  as such,
        # the write action we're checking for probably happened recently
        my $db = LJ::S1::get_s1style_writer($u);
        return $db->selectrow_hashref("SELECT * FROM s1style WHERE userid=? AND type=? AND styledes=?",
                                        undef, $u->{'userid'}, $type, $styledes);

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        return $dbh->selectrow_hashref("SELECT * FROM style WHERE user=? AND type=? AND styledes=?",
                                       undef, $u->{'user'}, $type, $styledes);
    }
}

# returns undef if style isn't clustered
sub get_style_userid {
    my $styleid = shift;

    # check cache
    my $userid = $LJ::S1::REQ_CACHE_STYLEMAP{$styleid};
    return $userid if $userid;

    my $memkey = [$styleid, "s1stylemap:$styleid"];
    my $style = LJ::MemCache::get($memkey);
    return $style if $style;

    # fetch from db
    my $dbr = LJ::get_db_reader();
    $userid = $dbr->selectrow_array("SELECT userid FROM s1stylemap WHERE styleid=?",
                                    undef, $styleid);
    return unless $userid;

    # set cache
    $LJ::S1::REQ_CACHE_STYLEMAP{$styleid} = $userid;
    LJ::MemCache::set($memkey, $userid);

    return $userid;
}

sub create_style {
    my ($u, $opts) = @_;
    return unless LJ::isu($u) && ref $opts eq 'HASH';

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $styleid = LJ::alloc_global_counter('S');
    return undef unless $styleid;

    my (@cols, @bind, @vals);
    foreach (qw(styledes type formatdata is_public is_embedded is_colorfree opt_cache has_ads)) {
        next unless $opts->{$_};

        push @cols, $_;
        push @bind, "?";
        push @vals, $opts->{$_};
    }
    my $cols = join(",", @cols);
    my $bind = join(",", @bind);
    return unless @cols;

    if ($u->{'dversion'} >= 5) {
        my $db = LJ::S1::get_s1style_writer($u);
        $db->do("INSERT INTO s1style (styleid,userid,$cols) VALUES (?,?,$bind)",
                undef, $styleid, $u->{'userid'}, @vals);
        my $insertid = LJ::User::mysql_insertid($db);
        die "Couldn't allocate insertid for s1style for userid $u->{userid}" unless $insertid;

        $dbh->do("INSERT INTO s1stylemap (styleid, userid) VALUES (?,?)", undef, $insertid, $u->{'userid'});
        return $insertid;

    } else {
        $dbh->do("INSERT INTO style (styleid, user,$cols) VALUES (?,?,$bind)",
                 undef, $styleid, $u->{'user'}, @vals);
        return $dbh->{'mysql_insertid'};
    }
}

sub update_style {
    my ($styleid, $opts) = @_;
    return unless $styleid && ref $opts eq 'HASH';

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    my @cols = qw(styledes type formatdata is_public is_embedded
                  is_colorfree opt_cache has_ads lastupdate);

    # what table to operate on ?
    my ($db, $table);

    # clustered table
    if ($u && $u->{'dversion'} >= 5) {
        $db = LJ::S1::get_s1style_writer($u);
        $table = "s1style";

    # global table
    } else {
        $db = LJ::get_db_writer();
        $table = "style";
    }

    my (@sets, @vals);
    foreach (@cols) {
        if ($opts->{$_}) {
            push @sets, "$_=?";
            push @vals, $opts->{$_};
        }
    }

    # update style
    my $now_lastupdate = $opts->{'lastupdate'} ? ", lastupdate=NOW()" : '';
    my $rows = $db->do("UPDATE $table SET " . join(", ", @sets) . "$now_lastupdate WHERE styleid=?",
                       undef, @vals, $styleid);

    # clear out stylecache
    $db->do("UPDATE s1stylecache SET vars_stor=NULL, vars_cleanver=0 WHERE styleid=?",
            undef, $styleid);

    # update memcache keys
    LJ::MemCache::delete([$styleid, "s1style:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1style_all:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1styc:$styleid"]);

    return $rows;
}

sub delete_style {
    my $styleid = shift;
    return unless $styleid;

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    my $dbh = LJ::get_db_writer();

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        $dbh->do("DELETE FROM s1stylemap WHERE styleid=?", undef, $styleid);

        my $db = LJ::S1::get_s1style_writer($u);
        $db->do("DELETE FROM s1style WHERE styleid=?", undef, $styleid);
        $db->do("DELETE FROM s1stylecache WHERE styleid=?", undef, $styleid);

    # old global table
    } else {
        # they won't have an s1stylemap entry

        $dbh->do("DELETE FROM style WHERE styleid=?", undef, $styleid);
        $dbh->do("DELETE FROM s1stylecache WHERE styleid=?", undef, $styleid);
    }

    # clear out some memcache space
    LJ::MemCache::delete([$styleid, "s1style:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1style_all:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1stylemap:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1styc:$styleid"]);

    return;
}

sub get_overrides {
    my $u = shift;
    return unless LJ::isu($u);

    # try memcache
    my $memkey = [$u->{'userid'}, "s1overr:$u->{'userid'}"];
    my $overr = LJ::MemCache::get($memkey);
    return $overr if $overr;

    # new clustered table
    if ($u->{'dversion'} >= 5) {
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
        $overr = $db->selectrow_array("SELECT override FROM s1overrides WHERE userid=?", undef, $u->{'userid'});

    # old global table
    } else {
        my $dbh = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $overr = $dbh->selectrow_array("SELECT override FROM overrides WHERE user=?", undef, $u->{'user'});
    }

    # set in memcache
    LJ::MemCache::set($memkey, $overr);

    return $overr;
}

sub clear_overrides {
    my $u = shift;
    return unless LJ::isu($u);

    my $overr;
    my $db;

    # new clustered table
    if ($u->{'dversion'} >= 5) {
        $overr = $u->do("DELETE FROM s1overrides WHERE userid=?", undef, $u->{'userid'});
        $db = $u;

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        $overr = $dbh->do("DELETE FROM overrides WHERE user=?", undef, $u->{'user'});
        $db = $dbh;
    }

    # update s1usercache
    $db->do("UPDATE s1usercache SET override_stor=NULL WHERE userid=?",
            undef, $u->{'userid'});

    LJ::MemCache::delete([$u->{'userid'}, "s1uc:$u->{'userid'}"]);
    LJ::MemCache::delete([$u->{'userid'}, "s1overr:$u->{'userid'}"]);

    return $overr;
}

sub save_overrides {
    my ($u, $overr) = @_;
    return unless LJ::isu($u) && $overr;

    # new clustered table
    my $insertid;
    if ($u->{'dversion'} >= 5) {
        $u->do("REPLACE INTO s1overrides (userid, override) VALUES (?, ?)",
               undef, $u->{'userid'}, $overr);
        $insertid = $u->mysql_insertid;

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        $dbh->do("REPLACE INTO overrides (user, override) VALUES (?, ?)",
                 undef, $u->{'user'}, $overr);
        $insertid = $dbh->{'mysql_insertid'};
    }

    # update s1usercache
    my $override_stor = LJ::CleanHTML::clean_s1_style($overr);
    $u->do("UPDATE s1usercache SET override_stor=?, override_cleanver=? WHERE userid=?",
           undef, $override_stor, $LJ::S1::CLEANER_VERSION, $u->{'userid'});

    LJ::MemCache::delete([$u->{'userid'}, "s1uc:$u->{'userid'}"]);
    LJ::MemCache::delete([$u->{'userid'}, "s1overr:$u->{'userid'}"]);

    return $insertid;
}

package LJ;

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
    $_ = $vars->{$key};
    s/%%([\w:]+:)?([\w\-\']+)%%/$1 ? LJ::fvp_transform(lc($1), $vars, $hashref, $2) : $hashref->{$2}/eg;
    return $_;
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
        if ($trans eq "color") {
            return $vars->{"color-$attr"};
        }
        elsif ($trans eq "ue") {
            $ret = LJ::eurl($ret);
        }
        elsif ($trans eq "cons") {
            if ($attr eq "img") { return $LJ::IMGPREFIX; }
            if ($attr eq "siteroot") { return $LJ::SITEROOT; }
            if ($attr eq "sitename") { return $LJ::SITENAME; }
        }
        elsif ($trans eq "attr") {
            $ret =~ s/\"/&quot;/g;
            $ret =~ s/\'/&\#39;/g;
            $ret =~ s/</&lt;/g;
            $ret =~ s/>/&gt;/g;
            $ret =~ s/\]\]//g;  # so they can't end the parent's [attr[..]] wrapper
        }
        elsif ($trans eq "lc") {
            $ret = lc($ret);
        }
        elsif ($trans eq "uc") {
            $ret = uc($ret);
        }
        elsif ($trans eq "xe") {
            $ret = LJ::exml($ret);
        }
        elsif ($trans eq 'ljuser' or $trans eq 'ljcomm') {
            my $user = LJ::canonical_username($ret);
            $ret = LJ::ljuser($user);
        }
        elsif ($trans eq 'userurl') {
            my $u = LJ::load_user($ret);
            $ret = LJ::journal_base($u) if $u;
        }
    }
    return $ret;
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

sub current_mood_str {
    my ($pic, $moodname) = @_;

    my $ret = "";

    if ($pic) {
        $ret .= qq{<img src="$pic->{url}" align="absmiddle" width="$pic->{width}" height="$pic->{height}" vspace="1" alt="" /> };
    }
    $ret .= $moodname;

    return $ret;
}

sub prepare_event {
    my ($item, $vars, $prefix, $eventnum, $s2p) = @_;

    $s2p ||= {};

    my %date_format = %{LJ::date_s2_to_s1($item->{time})};

    my %event = ();
    $event{'eventnum'} = $eventnum;
    $event{'itemid'} = $item->{itemid};
    $event{'datetime'} = LJ::fill_var_props($vars, "${prefix}_DATE_FORMAT", \%date_format);
    if ($item->{subject}) {
        $event{'subject'} = LJ::fill_var_props($vars, "${prefix}_SUBJECT", {
            "subject" => $item->{subject},
        });
    }

    $event{'event'} = $item->{text};
    $event{'user'} = $item->{journal}{username};

    # Special case for friends view: userpic for friend
    if ($vars->{"${prefix}_FRIENDPIC"} && $item->{userpic} && $item->{userpic}{url}) {
        $event{friendpic} = LJ::fill_var_props($vars, "${prefix}_FRIENDPIC", {
            "width" => $item->{userpic}{width},
            "height" => $item->{userpic}{height},
            "src" => $item->{userpic}{url},
        });
    }

    # Special case for friends view: per-friend configured colors
    if ($s2p && $s2p->{friends}) {
        $event{fgcolor} = $s2p->{friends}{$item->{journal}{username}}{fgcolor}{as_string};
        $event{bgcolor} = $s2p->{friends}{$item->{journal}{username}}{bgcolor}{as_string};
    }

    if ($item->{comments}{enabled}) {
        my $itemargs = "journal=".$item->{journal}{username}."&ditemid=".$item->{itemid};

        $event{'talklinks'} = LJ::fill_var_props($vars, "${prefix}_TALK_LINKS", {
            'itemid' => $item->{itemid},
            'itemargs' => $itemargs,
            'urlpost' => $item->{comments}{post_url},
            'urlread' => $item->{comments}{read_url},
            'messagecount' => $item->{comments}{count},
            'readlink' => $item->{comments}{count} != 0 ? LJ::fill_var_props($vars, "${prefix}_TALK_READLINK", {
                'urlread' => $item->{comments}{read_url},
                'messagecount' => $item->{comments}{count} == -1 ? "?" : $item->{comments}{count},
                'mc-plural-s' => $item->{comments}{count} == 1 ? "" : "s",
                'mc-plural-es' => $item->{comments}{count} == 1 ? "" : "es",
                'mc-plural-ies' => $item->{comments}{count} == 1 ? "y" : "ies",
            }) : "",
        });
    }

    LJ::prepare_currents({
        'entry' => $item,
        'vars' => $vars,
        'prefix' => $prefix,
        'event' => \%event,
    });

    if ($item->{poster}{_u}{userid} != $item->{journal}{_u}{userid}) {
        my %altposter = ();

        $altposter{'poster'} = $item->{poster}{username};
        $altposter{'owner'} = $item->{journal}{username};
        $altposter{'fgcolor'} = $event{'fgcolor'}; # Only set for friends view
        $altposter{'bgcolor'} = $event{'bgcolor'}; # Only set for friends view

        if ($item->{userpic} && $item->{userpic}->{url} && $vars->{"${prefix}_ALTPOSTER_PIC"}) {
            $altposter{'pic'} = LJ::fill_var_props($vars, "${prefix}_ALTPOSTER_PIC", {
                "src" => $item->{userpic}{url},
                "width" => $item->{userpic}{width},
                "height" => $item->{userpic}{height},
            });
        }
        $event{'altposter'} = LJ::fill_var_props($vars, "${prefix}_ALTPOSTER", \%altposter);
    }

    my $var = "${prefix}_EVENT";
    if ($item->{security} eq "private" &&
        $vars->{"${prefix}_EVENT_PRIVATE"}) { $var = "${prefix}_EVENT_PRIVATE"; }
    if ($item->{security} eq "protected" &&
        $vars->{"${prefix}_EVENT_PROTECTED"}) { $var = "${prefix}_EVENT_PROTECTED"; }

    return LJ::fill_var_props($vars, $var, \%event);
    
}

# <LJFUNC>
# class: s1
# name: LJ::prepare_currents
# des: do all the current music/mood/weather/whatever stuff.  only used by ljviews.pl.
# args: dbarg, args
# des-args: hashref with keys: 'entry' (an S2 Entry object), 'vars' hashref with
#           keys being S1 variables and 'prefix' string which is LASTN, DAY, etc.
# </LJFUNC>
sub prepare_currents
{
    my $args = shift;

    my $datakey = $args->{'datakey'} || $args->{'itemid'}; # new || old

    my $entry = $args->{entry};

    my %currents = ();

    if (my $val = $entry->{metadata}{music}) {
        $currents{'Music'} = $val;
    }

    $currents{'Mood'} = LJ::current_mood_str($entry->{mood_icon}, $entry->{metadata}{mood});
    delete $currents{'Mood'} unless $currents{'Mood'};

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
# class: s1
# name: LJ::date_s2_to_s1
# des: Convert an S2 Date or DateTime object into an S1 date hash
# args: s2date
# des-s2date: the S2 date object to convert
# </LJFUNC>
sub date_s2_to_s1
{
    my ($s2d) = @_;
    my $dayofweek = S2::Builtin::LJ::Date__day_of_week([], $s2d);
    my $am = $s2d->{hour} < 12 ? 'am' : 'pm';
    my $h12h = $s2d->{hour} > 12 ? $s2d->{hour} - 12 : $s2d->{hour};
    $h12h ||= 12; # Fix up hour 0
    return {
        'dayshort' => LJ::Lang::day_short($dayofweek),
        'daylong' => LJ::Lang::day_long($dayofweek),
        'monshort' => LJ::Lang::month_short($s2d->{month}),
        'monlong' => LJ::Lang::month_long($s2d->{month}),
        'yy' => substr($s2d->{year}, -2),
        'yyyy' => $s2d->{year},
        'm' => $s2d->{month},
        'mm' => sprintf("%02i", $s2d->{month}),
        'd' => $s2d->{day},
        'dd' => sprintf("%02i", $s2d->{day}),
        'dth' => $s2d->{day}.LJ::Lang::day_ord($s2d->{day}),
        'ap' => substr($am,1),
        'AP' => substr(uc($am),1),
        'ampm' => $am,
        'AMPM' => uc($am),
        'min' => sprintf("%02i", $s2d->{min}),
	'12h' => $h12h,
        '12hh' => sprintf("%02i", $h12h),
        '24h' => $s2d->{hour},
        '24hh' => sprintf("%02i", $s2d->{hour}),
    };
}

package LJ::S1;
use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";

# the creator for the 'lastn' view:
sub create_view_lastn
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'LASTN_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::RecentPage($u, $remote, $opts);

    my %lastn_page = ();
    $lastn_page{'name'} = $s2p->{journal}{name};
    $lastn_page{'name-\'s'} = ($lastn_page{'name'} =~ /s$/i) ? "'" : "'s";
    $lastn_page{'username'} = $s2p->{journal}{username};
    $lastn_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $lastn_page{'name'} . $lastn_page{'name-\'s'} . " Journal");
    $lastn_page{'numitems'} = $vars->{'LASTN_OPT_ITEMS'} || 20;

    $lastn_page{'urlfriends'} = $s2p->{view_url}{friends};
    $lastn_page{'urlcalendar'} = $s2p->{view_url}{archive};

    if ($s2p->{journal}{website_url}) {
        $lastn_page{'website'} =
            LJ::fill_var_props($vars, 'LASTN_WEBSITE', {
                "url" => $s2p->{journal}{website_url},
                "name" => $s2p->{journal}{website_name} || "My Website",
            });
    }

    $lastn_page{'events'} = "";
    $lastn_page{'head'} = $s2p->{head_content};

    $lastn_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    my $events = \$lastn_page{'events'};

    if ($s2p->{journal}{default_pic}{url}) {
        my $pic = $s2p->{journal}{default_pic};
        $lastn_page{'userpic'} =
            LJ::fill_var_props($vars, 'LASTN_USERPIC', {
                "src" => $pic->{url},
                "width" => $pic->{width},
                "height" => $pic->{height},
            });
    }

    my $eventnum = 0;
    my $firstday = 1;
    foreach my $item (@{$s2p->{entries}}) {
        if ($item->{new_day}) {
            my %date_format = %{LJ::date_s2_to_s1($item->{time})};
            my %new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth)) {
                $new_day{$_} = $date_format{$_};
            }
            unless ($firstday) {
                $$events .= LJ::fill_var_props($vars, "LASTN_END_DAY", {});
            }
            $$events .= LJ::fill_var_props($vars, "LASTN_NEW_DAY", \%new_day);

            $firstday = 0;
        }

        $$events .= LJ::prepare_event($item, $vars, 'LASTN', $eventnum++);
    }

    $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});

    if ($s2p->{nav}{skip}) {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
                "numitems" => $s2p->{nav}{count},
                "skip" => $s2p->{nav}{skip},
            });
    } else {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
                "numitems" => $s2p->{nav}{count},
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    if ($s2p->{nav}{forward_url}) {
        $skip_f = 1;

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
                "numitems" => $s2p->{nav}{forward_count},
                "url" => $s2p->{nav}{forward_url},
            });
    }

    my $maxskip = $LJ::MAX_SCROLLBACK_LASTN - $vars->{'LASTN_OPT_ITEMS'};

    if ($s2p->{nav}{backward_url}) {
        $skip_b = 1;

        $skiplinks{'skipbackward'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                "numitems" => $s2p->{nav}{backward_count},
                "url" => $s2p->{nav}{backward_url},
            });
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
        $skiplinks{'skipspacer'} = $vars->{'LASTN_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $lastn_page{'skiplinks'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_LINKS', \%skiplinks);
    }

    $$ret = LJ::fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;

    $$ret = "";

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'FRIENDS_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::FriendsPage($u, $remote, $opts);
    return $s2p if ref $s2p ne 'HASH';

    my %friends_page = ();
    $friends_page{'name'} = $s2p->{journal}{name};
    $friends_page{'name-\'s'} = ($friends_page{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $s2p->{journal}{username};
    $friends_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                       $friends_page{'name'} . $friends_page{'name-\'s'} . " Journal");
    $friends_page{'numitems'} = $vars->{'FRIENDS_OPT_ITEMS'} || 20;

    $friends_page{'urllastn'} = $s2p->{view_url}{recent};
    $friends_page{'urlcalendar'} = $s2p->{view_url}{archive};

    if ($s2p->{journal}{website_url}) {
        $friends_page{'website'} =
            LJ::fill_var_props($vars, 'FRIENDS_WEBSITE', {
                "url" => $s2p->{journal}{website_url},
                "name" => $s2p->{journal}{website_name} || "My Website",
            });
    }

    $friends_page{'events'} = "";

    unless (%{$s2p->{friends}}) {
        $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
          "name" => $friends_page{'name'},
          "name-\'s" => $friends_page{'name-\'s'},
          "username" => $friends_page{'username'},
        });

        $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
        return 1;
    }

    my %friends_events = ();
    my $events = \$friends_events{'events'};

    my $firstday = 1;
    my $eventnum = 0;

    foreach my $item (@{$s2p->{entries}}) {
        if ($item->{new_day}) {
            my %date_format = %{LJ::date_s2_to_s1($item->{time})};
            my %new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth)) {
                $new_day{$_} = $date_format{$_};
            }
            unless ($firstday) {
                $$events .= LJ::fill_var_props($vars, "FRIENDS_END_DAY", {});
            }
            $$events .= LJ::fill_var_props($vars, "FRIENDS_NEW_DAY", \%new_day);

            $firstday = 0;
        }

        $$events .= LJ::prepare_event($item, $vars, 'FRIENDS', $eventnum++, $s2p);
    }

    $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    if ($s2p->{nav}{skip}) {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
                "numitems" => $s2p->{nav}{count},
                "skip" => $s2p->{nav}{skip},
            });
    } else {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
                "numitems" => $s2p->{nav}{count},
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    if ($s2p->{nav}{forward_url}) {
        $skip_f = 1;

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
                "numitems" => $s2p->{nav}{forward_count},
                "url" => $s2p->{nav}{forward_url},
            });
    }

    if ($s2p->{nav}{backward_url}) {
        $skip_b = 1;

        $skiplinks{'skipbackward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
                "numitems" => $s2p->{nav}{backward_count},
                "url" => $s2p->{nav}{backward_url},
            });
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
        $skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $friends_page{'skiplinks'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }

    $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

    return 1;
}

# the creator for the 'calendar' view:
sub create_view_calendar
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'LASTN_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::YearPage($u, $remote, $opts);

    my $user = $u->{'user'};

    my %calendar_page = ();
    $calendar_page{'name'} = $s2p->{journal}{name};
    $calendar_page{'name-\'s'} = ($calendar_page{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    $calendar_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $calendar_page{'name'} . $calendar_page{'name-\'s'} . " Journal");

    $calendar_page{'urlfriends'} = $s2p->{view_url}{friends};
    $calendar_page{'urllastn'} = $s2p->{view_url}{recent};

    $calendar_page{'head'} = $s2p->{head_content};
    $calendar_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};

    if ($s2p->{journal}{website_url}) {
        $calendar_page{'website'} = LJ::fill_var_props($vars, 'CALENDAR_WEBSITE', {
            "url" => $s2p->{journal}{website_url},
            "name" => $s2p->{journal}{website_name} || "My Website",
        });
    }

    $calendar_page{'months'} = "";
    my $months = \$calendar_page{'months'};

    if (scalar(@{$s2p->{years}}) > 1) {
        my $yearlinks = "";
        foreach my $year ($vars->{CALENDAR_SORT_MODE} eq 'reverse' ? reverse @{$s2p->{years}} : @{$s2p->{years}}) {
            my $yy = sprintf("%02d", $year->{year} % 100);
            my $url = $year->{url};
            unless ($year->{displayed}) {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year->{year}, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year->{year}, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} = LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
        'yyyy' => $s2p->{year},
        'yy' => substr($s2p->{year}, 2, 2),
    });

    foreach my $month ($vars->{CALENDAR_SORT_MODE} eq 'reverse' ? reverse @{$s2p->{months}} : @{$s2p->{months}}) {
	next unless $month->{has_entries};

        my %calendar_month = ();
        $calendar_month{'monlong'} = LJ::Lang::month_long($month->{month});
        $calendar_month{'monshort'} = LJ::Lang::month_short($month->{month});
        $calendar_month{'yyyy'} = $month->{year};
        $calendar_month{'yy'} = substr($calendar_month{'yyyy'}, 2, 2);
        $calendar_month{'weeks'} = "";
        $calendar_month{'urlmonthview'} = $month->{url};
        my $weeks = \$calendar_month{'weeks'};

	foreach my $week (@{$month->{weeks}}) {
            my %calendar_week = ();

            $calendar_week{emptydays_beg} = LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', { "numempty" => $week->{pre_empty} }) if $week->{pre_empty};
            $calendar_week{emptydays_end} = LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', { "numempty" => $week->{post_empty} }) if $week->{post_empty};
            $calendar_week{days} = "";
            my $days = \$calendar_week{days};

            foreach my $day (@{$week->{days}}) {
                my %calendar_day = ();

                $calendar_day{d} = $day->{date}{day};
                $calendar_day{eventcount} = $day->{num_entries};
                $calendar_day{dayevent} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    eventcount => $day->{num_entries},
                    dayurl => $day->{url},
                }) if $day->{num_entries};
                $calendar_day{daynoevent} = LJ::fill_var_props($vars, 'CALENDAR_DAY_NOEVENT', {}) unless $day->{num_entries};

                $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);
            }

            $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
        }
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
    }

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;
}

# the creator for the 'day' view:
sub create_view_day
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'LASTN_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::DayPage($u, $remote, $opts);

    my $user = $u->{'user'};

    my %day_page = ();
    $day_page{'name'} = $s2p->{journal}{name};
    $day_page{'name-\'s'} = ($day_page{'name'} =~ /s$/i) ? "'" : "'s";
    $day_page{'username'} = $user;
    $day_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                   $day_page{'name'} . $day_page{'name-\'s'} . " Journal");

    $day_page{'urlfriends'} = $s2p->{view_url}{friends};
    $day_page{'urllastn'} = $s2p->{view_url}{recent};
    $day_page{'urlcalendar'} = $s2p->{view_url}{archive};

    $day_page{'head'} = $s2p->{head_content};
    $day_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};

    if ($s2p->{journal}{website_url}) {
        $day_page{'website'} = LJ::fill_var_props($vars, 'DAY_WEBSITE', {
            "url" => $s2p->{journal}{website_url},
            "name" => $s2p->{journal}{website_name} || "My Website",
        });
    }

    my $date = LJ::date_s2_to_s1($s2p->{date});
    map { $day_page{$_} = $date->{$_} } qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth);

    $day_page{'prevday_url'} = $s2p->{prev_url};
    $day_page{'nextday_url'} = $s2p->{next_url};

    $day_page{'events'} = "";
    my $events = \$day_page{'events'};

    my $entries = $s2p->{entries};
    if (@$entries) {
        my $inevents = "";
        foreach my $item ($vars->{DAY_SORT_MODE} eq 'reverse' ? reverse @$entries : @$entries) {
            $inevents .= LJ::prepare_event($item, $vars, 'DAY');
        }
        $$events = LJ::fill_var_props($vars, 'DAY_EVENTS', { events => $inevents });
    }
    else {
        $$events = LJ::fill_var_props($vars, 'DAY_NOEVENTS', {});
    }

    $$ret .= LJ::fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

1;
