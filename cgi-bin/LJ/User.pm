#
# LiveJournal user object
#
# 2004-07-21: we're transition from $u hashrefs to $u objects, currently
#             backed by hashrefs, to ease migration.  in the future,
#             more methods from ljlib.pl and other places will move here,
#             and the representation of a $u object will change to 'fields'.
#             at present, the motivation to moving to $u objects is to do
#             all database access for a given user through his/her $u object
#             so the queries can be tagged for use by the star replication
#             daemon.

use strict;

package LJ::User;
use Carp;
use lib "$ENV{'LJHOME'}/cgi-bin";
use LJ::MemCache;

sub readonly {
    my $u = shift;
    return LJ::get_cap($u, "readonly");
}

# returns self (the $u object which can be used for $u->do) if
# user is writable, else 0
sub writer {
    my $u = shift;
    return $u if $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return 0;
}

# returns a true value if the user is underage; or if you give it an argument,
# will turn on/off that user's underage status.  can also take a second argument
# when you're setting the flag to also update the underage_status userprop
# which is used to record if a user was ever marked as underage.
sub underage {
    # has no bearing if this isn't on
    return undef unless $LJ::UNDERAGE_BIT;

    # now get the args and continue
    my $u = shift;
    return LJ::get_cap($u, 'underage') unless @_;

    # now set it on or off
    my $on = shift() ? 1 : 0;
    if ($on) {
        LJ::modify_caps($u, [ $LJ::UNDERAGE_BIT ], []);
        $u->{caps} |= 1 << $LJ::UNDERAGE_BIT;
    } else {
        LJ::modify_caps($u, [], [ $LJ::UNDERAGE_BIT ]);
        $u->{caps} &= !(1 << $LJ::UNDERAGE_BIT);
    }

    # now set their status flag if one was sent
    my $status = shift();
    if ($status || $on) {
        # by default, just records if user was ever underage ("Y")
        $u->underage_status($status || 'Y');
    }

    # add to statushistory
    if (my $shwhen = shift()) {
        my $text = $on ? "marked" : "unmarked";
        my $status = $u->underage_status;
        LJ::statushistory_add($u, undef, "coppa", "$text; status=$status; when=$shwhen");
    }

    # now fire off any hooks that are available
    LJ::run_hooks('set_underage', {
        u => $u,
        on => $on,
        status => $u->underage_status,
    });

    # return what we set it to
    return $on;
}

# log a line to our userlog
sub log_event {
    my $u = shift;

    my ($type, $info) = @_;
    return undef unless $type;
    $info ||= {};

    # now get variables we need; we use delete to remove them from the hash so when we're
    # done we can just encode what's left
    my $ip = delete($info->{ip}) || LJ::get_remote_ip() || undef;
    my $uniq = delete $info->{uniq};
    unless ($uniq) {
        eval {
            $uniq = Apache->request->notes('uniq');
        };
    }
    my $remote = delete($info->{remote}) || LJ::get_remote() || undef;
    my $targetid = (delete($info->{actiontarget})+0) || undef;
    my $extra = %$info ? join('&', map { LJ::eurl($_) . '=' . LJ::eurl($info->{$_}) } keys %$info) : undef;

    # now insert the data we have
    $u->do("INSERT INTO userlog (userid, logtime, action, actiontarget, remoteid, ip, uniq, extra) " .
           "VALUES (?, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?)", undef, $u->{userid}, $type,
           $targetid, $remote ? $remote->{userid} : undef, $ip, $uniq, $extra);
    return undef if $u->err;
    return 1;
}

# return or set the underage status userprop
sub underage_status {
    return undef unless $LJ::UNDERAGE_BIT;

    my $u = shift;

    # return if they aren't setting it
    unless (@_) {
        LJ::load_user_props($u, 'underage_status');
        return $u->{underage_status};
    }

    # set and return what it got set to
    LJ::set_userprop($u, 'underage_status', shift());
    return $u->{underage_status};
}

# returns a true value if user has a reserved 'ext' name.
sub external {
    my $u = shift;
    return $u->{user} =~ /^ext_/;
}

# this is for debugging/special uses where you need to instruct
# a user object on what database handle to use.  returns the
# handle that you gave it.
sub set_dbcm {
    my $u = shift;
    return $u->{'_dbcm'} = shift;
}

sub begin_work {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    my $rv = $dbcm->begin_work;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub commit {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    my $rv = $dbcm->commit;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub rollback {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    my $rv = $dbcm->rollback;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

# get an $sth from the writer
sub prepare {
    my $u = shift;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    my $rv = $dbcm->prepare(@_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

# $u->do("UPDATE foo SET key=?", undef, $val);
sub do {
    my $u = shift;
    my $query = shift;

    my $uid = $u->{userid}+0
        or croak "Database update called on null user object";

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    $query =~ s!^(\s*\w+\s+)!$1/* uid=$uid */ !;

    my $rv = $dbcm->do($query, @_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    $u->{_mysql_insertid} = $dbcm->{'mysql_insertid'} if $dbcm->{'mysql_insertid'};

    return $rv;
}

sub selectrow_array {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";
    return $dbcm->selectrow_array(@_);
}

sub selectrow_hashref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";
    return $dbcm->selectrow_hashref(@_);
}

sub err {
    my $u = shift;
    return $u->{_dberr};
}

sub errstr {
    my $u = shift;
    return $u->{_dberrstr};
}

sub quote {
    my $u = shift;
    my $text = shift;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak "Database handle unavailable";

    return $dbcm->quote($text);
}

sub mysql_insertid {
    my $u = shift;
    if ($u->isa("LJ::User")) {
        return $u->{_mysql_insertid};
    } elsif (LJ::isdb($u)) {
        my $db = $u;
        return $db->{'mysql_insertid'};
    } else {
        die "Unknown object '$u' being passed to LJ::User::mysql_insertid.";
    }
}

# <LJFUNC>
# name: LJ::User::dudata_set
# class: logging
# des: Record or delete disk usage data for a journal
# args: u, area, areaid, bytes
# area: One character: "L" for log, "T" for talk, "B" for bio, "P" for pic.
# areaid: Unique ID within $area, or '0' if area has no ids (like bio)
# bytes: Number of bytes item takes up.  Or 0 to delete record.
# returns: 1.
# </LJFUNC>
sub dudata_set {
    my ($u, $area, $areaid, $bytes) = @_;
    $bytes += 0; $areaid += 0;
    if ($bytes) {
        $u->do("REPLACE INTO dudata (userid, area, areaid, bytes) ".
               "VALUES (?, ?, $areaid, $bytes)", undef,
               $u->{userid}, $area);
    } else {
        $u->do("DELETE FROM dudata WHERE userid=? AND ".
               "area=? AND areaid=$areaid", undef,
               $u->{userid}, $area);
    }
    return 1;
}

sub generate_session
{
    my ($u, $opts) = @_;
    my $udbh = LJ::get_cluster_master($u);
    return undef unless $udbh;

    # clean up any old, expired sessions they might have (lazy clean)
    $u->do("DELETE FROM sessions WHERE userid=? AND timeexpire < UNIX_TIMESTAMP()",
           undef, $u->{userid});

    my $sess = {};
    $opts->{'exptype'} = "short" unless $opts->{'exptype'} eq "long" ||
                                        $opts->{'exptype'} eq "once";
    $sess->{'auth'} = LJ::rand_chars(10);
    my $expsec = $opts->{'expsec'}+0 || {
        'short' => 60*60*24*1.5, # 36 hours
        'long' => 60*60*24*60,   # 60 days
        'once' => 60*60*24*1.5,  # same as short; just doesn't renew
    }->{$opts->{'exptype'}};
    my $id = LJ::alloc_user_counter($u, 'S');
    return undef unless $id;
    $u->do("REPLACE INTO sessions (userid, sessid, auth, exptype, ".
           "timecreate, timeexpire, ipfixed) VALUES (?,?,?,?,UNIX_TIMESTAMP(),".
           "UNIX_TIMESTAMP()+$expsec,?)", undef,
           $u->{'userid'}, $id, $sess->{'auth'}, $opts->{'exptype'}, $opts->{'ipfixed'});
    return undef if $u->err;
    $sess->{'sessid'} = $id;
    $sess->{'userid'} = $u->{'userid'};
    $sess->{'ipfixed'} = $opts->{'ipfixed'};
    $sess->{'exptype'} = $opts->{'exptype'};

    # clean up old sessions
    my $old = $udbh->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
                                        "userid=$u->{'userid'} AND ".
                                        "timeexpire < UNIX_TIMESTAMP()");
    $u->kill_sessions(@$old) if $old;

    # mark account as being used
    LJ::mark_user_active($u, 'login');

    return $sess;
}

sub make_login_session {
    my ($u, $exptype, $ipfixed) = @_;
    $exptype ||= 'short';
    return 0 unless $u;

    my $etime = 0;
    eval { Apache->request->notes('ljuser' => $u->{'user'}); };

    my $sess = $u->generate_session({
        'exptype' => $exptype,
        'ipfixed' => $ipfixed,
    });
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

    LJ::mark_user_active($u, 'login');

    return 1;
}

sub tosagree_set 
{
    my ($u, $err) = @_;
    return undef unless $u;

    unless (-f "$LJ::HOME/htdocs/inc/legal-tos") {
        $$err = "TOS include file could not be found";
        return undef;
    }

    my $rev;
    open (TOS, "$LJ::HOME/htdocs/inc/legal-tos");
    while ((!$rev) && (my $line = <TOS>)) {
        my $rcstag = "Revision";
        if ($line =~ /\$$rcstag:\s*(\S+)\s*\$/) {
            $rev = $1;
        }
    }
    close TOS;

    # if the required version of the tos is not available, error!
    my $rev_req = $LJ::REQUIRED_TOS{rev};
    if ($rev_req > 0 && $rev ne $rev_req) {
        $$err = "Required Terms of Service revision is $rev_req, but system version is $rev.";
        return undef;
    }

    my $newval = join(', ', time(), $rev);
    my $rv = LJ::set_userprop($u, "legal_tosagree", $newval);

    # set in $u object for callers later
    $u->{legal_tosagree} = $newval if $rv;

    return $rv;
}

sub tosagree_verify {
    my $u = shift;

    return 1 unless $LJ::TOS_CHECK;

    my $rev_req = $LJ::REQUIRED_TOS{rev};
    return 1 unless $rev_req > 0;

    LJ::load_user_props($u, 'legal_tosagree')
        unless $u->{legal_tosagree};

    my $rev_cur = (split(/\s*,\s*/, $u->{legal_tosagree}))[1];

    return $rev_cur eq $rev_req;
}

sub kill_sessions {
    my $u = shift;
    my (@sessids) = @_;
    my $in = join(',', map { $_+0 } @sessids);
    return 1 unless $in;
    my $userid = $u->{'userid'};
    foreach (qw(sessions sessions_data)) {
        $u->do("DELETE FROM $_ WHERE userid=? AND ".
               "sessid IN ($in)", undef, $userid);
    }
    foreach my $id (@sessids) {
        $id += 0;
        my $memkey = [$userid,"sess:$userid:$id"];
        LJ::MemCache::delete($memkey);
    }
    return 1;
}

sub kill_all_sessions {
    my $u = shift;
    return 0 unless $u;
    my $udbh = LJ::get_cluster_master($u);
    my $sessions = $udbh->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
                                             "userid=$u->{'userid'}");
    $u->kill_sessions(@$sessions) if @$sessions;

    # forget this user, if we knew they were logged in
    delete $BML::COOKIE{'ljsession'};
    LJ::set_remote(undef) if
        $LJ::CACHE_REMOTE &&
        $LJ::CACHE_REMOTE->{userid} == $u->{userid};

    return 1;
}

sub kill_session {
    my $u = shift;
    return 0 unless $u;
    return 0 unless exists $u->{'_session'};
    $u->kill_sessions($u->{'_session'}->{'sessid'});

    # forget this user, if we knew they were logged in
    delete $BML::COOKIE{'ljsession'};
    LJ::set_remote(undef) if
        $LJ::CACHE_REMOTE &&
        $LJ::CACHE_REMOTE->{userid} == $u->{userid};

    return 1;
}

# <LJFUNC>
# name: LJ::User::mogfs_userpic_key
# class: mogilefs
# des: Make a mogilefs key for the given pic for the user
# args: pic
# pic: Either the userpic hash or the picid of the userpic.
# returns: 1.
# </LJFUNC>
sub mogfs_userpic_key {
    my $self = shift or return undef;
    my $pic = shift or croak "missing required arg: userpic";

    my $picid = ref $pic ? $pic->{picid} : $pic+0;
    return "up:$self->{userid}:$picid";
}

# all reads/writes to talk2 must be done inside a lock, so there's
# no race conditions between reading from db and putting in memcache.
# can't do a db write in between those 2 steps.  the talk2 -> memcache
# is elsewhere (talklib.pl), but this $dbh->do wrapper is provided
# here because non-talklib things modify the talk2 table, and it's
# nice to centralize the locking rules.
#
# return value is return of $dbh->do.  $errref scalar ref is optional, and
# if set, gets value of $dbh->errstr
#
# write:  (LJ::talk2_do)
#   GET_LOCK
#    update/insert into talk2
#   RELEASE_LOCK
#    delete memcache
#
# read:   (LJ::Talk::get_talk_data)
#   try memcache
#   GET_LOCk
#     read db
#     update memcache
#   RELEASE_LOCK

sub talk2_do {
    my ($u, $nodetype, $nodeid, $errref, $sql, @args) = @_;
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    return undef unless $u->writer;

    my $dbcm = $u->{_dbcm};

    my $memkey = [$u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid"];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @args);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    LJ::MemCache::delete($memkey, 0) if int($ret);
    return $ret;
}

# log2_do
# see comments for talk2_do

sub log2_do {
    my ($u, $errref, $sql, @args) = @_;
    return undef unless $u->writer;

    my $dbcm = $u->{_dbcm};

    my $memkey = [$u->{'userid'}, "log2lt:$u->{'userid'}"];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @args);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    LJ::MemCache::delete($memkey, 0) if int($ret);
    return $ret;
}

sub url {
    my $u = shift;
    LJ::load_user_props($u, "url");
    if ($u->{'journaltype'} eq "I" && ! $u->{url}) {
        my $id = $u->identity;
        if ($id && $id->[0] eq "O") {
            LJ::set_userprop($u, "url", $id->[1]) if $id->[1];
            return $id->[1];
        }
    }
    return $u->{url};
}

# returns arrayref of [idtype, identity]
sub identity {
    my $u = shift;
    return $u->{_identity} if $u->{_identity};
    my $memkey = [$u->{userid}, "ident:$u->{userid}"];
    my $ident = LJ::MemCache::get($memkey);
    if ($ident) {
        return $u->{_identity} = $ident;
    }

    my $dbh = LJ::get_db_writer();
    $ident = $dbh->selectrow_arrayref("SELECT idtype, identity FROM identitymap ".
                                      "WHERE userid=? LIMIT 1", undef, $u->{userid});
    if ($ident) {
        LJ::MemCache::set($memkey, $ident);
        return $ident;
    }
    return undef;
}

sub ljuser_display {
    my $u = shift;
    my $opts = shift;

    return LJ::ljuser($u, $opts) unless $u->{'journaltype'} eq "I";

    my $id = $u->identity;
    return "<b>????</b>" unless $id;

    my $andfull = $opts->{'full'} ? "&amp;mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';

    my ($url, $name);

    if ($id->[0] eq "O") {
        require Net::OpenID::Consumer;
        $url = $id->[1];
        $name = Net::OpenID::VerifiedIdentity::DisplayOfURL($url);
        # FIXME: make a good out of this
        $name =~ s/\[(live|dead)journal\.com/\[${1}journal/;

        $url ||= "about:blank";
        $name ||= "[no_name]";

        return "<span class='ljuser' style='white-space: nowrap;'><a href='$LJ::SITEROOT/userinfo.bml?userid=$u->{userid}&amp;t=I$andfull'><img src='$img/openid-profile.gif' alt='[info]' width='16' height='16' style='vertical-align: bottom; border: 0;' /></a><a href='$url'><b>$name</b></a></span>";

    } else {
        return "<b>????</b>";
    }
}

1;
