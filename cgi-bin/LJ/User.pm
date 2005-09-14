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
    return 1 unless $LJ::INNODB_DB{$u->{clusterid}};

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
    return 1 unless $LJ::INNODB_DB{$u->{clusterid}};

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
    return 0 unless $LJ::INNODB_DB{$u->{clusterid}};

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
        if ($id && $id->typeid == 0) {
            LJ::set_userprop($u, "url", $id->[1]) if $id->[1];
            return $id->value;
        }
    }
    return $u->{url};
}

# returns LJ::Identity object
sub identity {
    my $u = shift;
    return $u->{_identity} if $u->{_identity};
    return undef unless $u->{'journaltype'} eq "I";

    require LJ::Identity;

    my $memkey = [$u->{userid}, "ident:$u->{userid}"];
    my $ident = LJ::MemCache::get($memkey);
    if ($ident) {
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );

        return $u->{_identity} = $i;
    }

    my $dbh = LJ::get_db_writer();
    $ident = $dbh->selectrow_arrayref("SELECT idtype, identity FROM identitymap ".
                                      "WHERE userid=? LIMIT 1", undef, $u->{userid});
    if ($ident) {
        LJ::MemCache::set($memkey, $ident);
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );
        return $i;
    }
    return undef;
}

# returns a URL if account is an OpenID identity.  undef otherwise.
sub openid_identity {
    my $u = shift;
    my $ident = $u->identity;
    return undef unless $ident && $ident->typeid == 0;
    return $ident->value;
}

# returns username or identity display name, not escaped
sub display_name {
    my $u = shift;
    return $u->{'user'} unless $u->{'journaltype'} eq "I";

    my $id = $u->identity;
    return "[ERR:unknown_identity]" unless $id;

    my ($url, $name);
    if ($id->typeid == 0) {
        require Net::OpenID::Consumer;
        $url = $id->value;
        $name = Net::OpenID::VerifiedIdentity::DisplayOfURL($url, $LJ::IS_DEV_SERVER);
        $name = LJ::run_hook("identity_display_name", $name) || $name;
    }
    return $name;
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

    if ($id->typeid == 0) {
        $url = $id->value;
        $name = $u->display_name;

        $url ||= "about:blank";
        $name ||= "[no_name]";

        $url = LJ::ehtml($url);
        $name = LJ::ehtml($name);

        return "<span class='ljuser' style='white-space: nowrap;'><a href='$LJ::SITEROOT/userinfo.bml?userid=$u->{userid}&amp;t=I$andfull'><img src='$img/openid-profile.gif' alt='[info]' width='16' height='16' style='vertical-align: bottom; border: 0;' /></a><a href='$url' rel='nofollow'><b>$name</b></a></span>";

    } else {
        return "<b>????</b>";
    }
}

# class function
sub load_identity_user {
    my ($type, $ident, $vident) = @_;

    my $dbh = LJ::get_db_writer();
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, $type, $ident);
    return LJ::load_userid($uid) if $uid;

    # increment ext_ counter until we successfully create an LJ
    # account.  hard cap it at 10 tries. (arbitrary, but we really
    # shouldn't have *any* failures here, let alone 10 in a row)

    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter('E');

        my $name = $extuser;
        if ($type eq "O" && ref $vident) {
            $name = $vident->display;
        }

        $uid = LJ::create_account({
            caps => undef,
            user => $extuser,
            name => $name,
            journaltype => 'I',
        });
        last if $uid;
        select undef, undef, undef, .10;  # lets not thrash over this
    }
    return undef unless $uid &&
        $dbh->do("INSERT INTO identitymap (idtype, identity, userid) VALUES (?,?,?)",
                 undef, $type, $ident, $uid);

    my $u = LJ::load_userid($uid);

    # record create information
    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    return $u;
}

# instance method:  returns userprop for a user.  currently from cache with no
# way yet to force master.
sub prop {
    my ($u, $prop) = @_;
    unless (exists $u->{$_}) {
        LJ::load_user_props($u, $prop);
    }
    return $u->{$prop};
}

sub journal_base {
    my $u = shift;
    return LJ::journal_base($u);
}

package LJ;

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
    return unless isu($u);
    return if $u->{'statusvis'} eq "X";

    my $opts = ref $_[0] ? shift : {};
    my (@props) = @_;

    my ($sql, $sth);
    LJ::load_props("user");

    ## user reference
    my $uid = $u->{'userid'}+0;
    $uid = LJ::get_userid($u->{'user'}) unless $uid;

    my $mem = {};
    my $use_master = 0;
    my $used_slave = 0;  # set later if we ended up using a slave

    if (@LJ::MEMCACHE_SERVERS) {
        my @keys;
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            die "Invalid userprop $_ passed to LJ::load_user_props." unless $p;
            push @keys, [$uid,"uprop:$uid:$p->{'id'}"];
        }
        $mem = LJ::MemCache::get_multi(@keys) || {};
        $use_master = 1;
    }

    $use_master = 1 if $opts->{'use_master'};

    my @needwrite;  # [propid, propname] entries we need to save to memcache later

    my %loadfrom;
    my %multihomed; # ( $propid => 0/1 ) # 0 if we haven't loaded it, 1 if we have
    unless (@props) {
        # case 1: load all props for a given user.
        # multihomed props are stored on userprop and userproplite2, but since they
        # should always be in sync, it doesn't matter which gets loaded first, the
        # net results should be the same.  see doc/designnotes/multihomed_props.txt
        # for more information.
        $loadfrom{'userprop'} = 1;
        $loadfrom{'userproplite'} = 1;
        $loadfrom{'userproplite2'} = 1;
        $loadfrom{'userpropblob'} = 1;
    } else {
        # case 2: load only certain things
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            die "Invalid userprop $_ passed to LJ::load_user_props." unless $p;
            if (defined $mem->{"uprop:$uid:$p->{'id'}"}) {
                $u->{$_} = $mem->{"uprop:$uid:$p->{'id'}"};
                next;
            }
            push @needwrite, [ $p->{'id'}, $_ ];
            my $source = $p->{'indexed'} ? "userprop" : "userproplite";
            if ($p->{datatype} eq 'blobchar') {
                $source = "userpropblob"; # clustered blob
            }
            elsif ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
                $source = "userproplite2";  # clustered
            }
            elsif ($p->{multihomed}) {
                $multihomed{$p->{id}} = 0;
                $source = "userproplite2";
            }
            push @{$loadfrom{$source}}, $p->{'id'};
        }
    }

    foreach my $table (qw{userproplite userproplite2 userpropblob userprop}) {
        next unless exists $loadfrom{$table};
        my $db;
        if ($use_master) {
            $db = ($table =~ m{userprop(lite2|blob)}) ?
                LJ::get_cluster_master($u) :
                LJ::get_db_writer();
        }
        unless ($db) {
            $db = ($table =~ m{userprop(lite2|blob)}) ?
                LJ::get_cluster_reader($u) :
                LJ::get_db_reader();
            $used_slave = 1;
        }
        $sql = "SELECT upropid, value FROM $table WHERE userid=$uid";
        if (ref $loadfrom{$table}) {
            $sql .= " AND upropid IN (" . join(",", @{$loadfrom{$table}}) . ")";
        }
        $sth = $db->prepare($sql);
        $sth->execute;
        while (my ($id, $v) = $sth->fetchrow_array) {
            delete $multihomed{$id} if $table eq 'userproplite2';
            $u->{$LJ::CACHE_PROPID{'user'}->{$id}->{'name'}} = $v;
        }

        # push back multihomed if necessary
        if ($table eq 'userproplite2') {
            push @{$loadfrom{userprop}}, $_ foreach keys %multihomed;
        }
    }

    # see if we failed to get anything above and need to hit the master.
    # this usually happens the first time a multihomed prop is hit.  this
    # code will propogate that prop down to the cluster.
    if (%multihomed) {

        # verify that we got the database handle before we try propogating data
        if ($u->writer) {
            my @values;
            foreach my $id (keys %multihomed) {
                my $pname = $LJ::CACHE_PROPID{user}{$id}{name};
                if (defined $u->{$pname} && $u->{$pname}) {
                    push @values, "($uid, $id, " . $u->quote($u->{$pname}) . ")";
                } else {
                    push @values, "($uid, $id, '')";
                }
            }
            $u->do("REPLACE INTO userproplite2 VALUES " . join ',', @values);
        }
    }

    # Add defaults to user object.

    # defaults for S1 style IDs in config file are magic: really
    # uniq strings representing style IDs, so on first use, we need
    # to map them
    unless ($LJ::CACHED_S1IDMAP) {

        my $pubsty = LJ::S1::get_public_styles();
        foreach (values %$pubsty) {
            my $k = "s1_$_->{'type'}_style";
            next unless $LJ::USERPROP_DEF{$k} eq "$_->{'type'}/$_->{'styledes'}";

            $LJ::USERPROP_DEF{$k} = $_->{'styleid'};
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

    unless ($used_slave) {
        my $expire = time() + 3600*24;
        foreach my $wr (@needwrite) {
            my ($id, $name) = ($wr->[0], $wr->[1]);
            LJ::MemCache::set([$uid,"uprop:$uid:$id"], $u->{$name} || "", $expire);
        }
    }
}

# simple interface to LJ::load_userids_multiple.  takes userids,
# returns hashref with keys ids, values $u refs.
sub load_userids
{
    my %u;
    LJ::load_userids_multiple([ map { $_ => \$u{$_} } @_ ]);
    return \%u;
}

# <LJFUNC>
# name: LJ::load_userids_multiple
# des: Loads a number of users at once, efficiently.
# info: loads a few users at once, their userids given in the keys of $map
#       listref (not hashref: can't have dups).  values of $map listref are
#       scalar refs to put result in.  $have is an optional listref of user
#       object caller already has, but is too lazy to sort by themselves.
# args: dbarg?, map, have, memcache_only?
# des-map: Arrayref of pairs (userid, destination scalarref)
# des-have: Arrayref of user objects caller already has
# des-memcache_only: Flag to only retrieve data from memcache
# returns: Nothing.
# </LJFUNC>
sub load_userids_multiple
{
    &nodb;
    my ($map, $have, $memcache_only) = @_;

    my $sth;

    my %need;
    while (@$map) {
        my $id = shift @$map;
        my $ref = shift @$map;
        next unless int($id);
        push @{$need{$id}}, $ref;

        if ($LJ::REQ_CACHE_USER_ID{$id}) {
            push @{$have}, $LJ::REQ_CACHE_USER_ID{$id};
        }
    }

    my $satisfy = sub {
        my $u = shift;
        next unless ref $u eq "LJ::User";
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
        foreach (LJ::memcache_get_u(map { [$_,"userid:$_"] } keys %need)) {
            $satisfy->($_);
        }
    }

    if (%need && ! $memcache_only) {
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        _load_user_raw($db, "userid", [ keys %need ], sub {
            my $u = shift;
            LJ::memcache_set_u($u);
            $satisfy->($u);
        });
    }
}

# des-db:  $dbh/$dbr
# des-key:  either "userid" or "user"  (the WHERE part)
# des-vals: value or arrayref of values for key to match on
# des-hoook: optional code ref to run for each $u
# returns: last $u found
sub _load_user_raw
{
    my ($db, $key, $vals, $hook) = @_;
    $hook ||= sub {};
    $vals = [ $vals ] unless ref $vals eq "ARRAY";

    my $use_isam;
    unless ($LJ::CACHE_NO_ISAM{user} || scalar(@$vals) > 10) {
        eval { $db->do("HANDLER user OPEN"); };
        if ($@ || $db->err) {
            $LJ::CACHE_NO_ISAM{user} = 1;
        } else {
            $use_isam = 1;
        }
    }

    my $last;

    if ($use_isam) {
        $key = "PRIMARY" if $key eq "userid";
        foreach my $v (@$vals) {
            my $sth = $db->prepare("HANDLER user READ `$key` = (?) LIMIT 1");
            $sth->execute($v);
            my $u = $sth->fetchrow_hashref;
            if ($u) {
                bless $u, 'LJ::User';
                $hook->($u);
                $last = $u;
            }
        }
        $db->do("HANDLER user close");
    } else {
        my $in = join(", ", map { $db->quote($_) } @$vals);
        my $sth = $db->prepare("SELECT * FROM user WHERE $key IN ($in)");
        $sth->execute;
        while (my $u = $sth->fetchrow_hashref) {
            bless $u, 'LJ::User';
            $hook->($u);
            $last = $u;
        }
    }

    return $last;
}

# <LJFUNC>
# name: LJ::load_user
# des: Loads a user record given a username.
# info: From the [dbarg[user]] table.
# args: dbarg?, user, force?
# des-user: Username of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_user
{
    &nodb;
    my ($user, $force) = @_;

    $user = LJ::canonical_username($user);
    return undef unless length $user;

    my $set_req_cache = sub {
        my $u = shift;
        $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u;
        $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u;
        return $u;
    };

    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "user", $user);
        return $u unless $u && $use_dbh;

        # set caches since we got a u from the master
        LJ::memcache_set_u($u);
        return $set_req_cache->($u);
    };

    # caller is forcing a master, return now
    return $get_user->("master") if $force;

    my $u;

    # return process cache if we have one
    $u = $LJ::REQ_CACHE_USER_NAME{$user};
    return $u if $u;

    # check memcache
    {
        my $uid = LJ::MemCache::get("uidof:$user");
        $u = LJ::memcache_get_u([$uid, "userid:$uid"]) if $uid;
        return $set_req_cache->($u) if $u;
    }

    # try to load from master if using memcache, otherwise from slave
    $u = $get_user->(scalar @LJ::MEMCACHE_SERVERS);
    return $u if $u;

    # setup LDAP handler if this is the first time
    if ($LJ::LDAP_HOST && ! $LJ::AUTH_EXISTS) {
        require LJ::LDAP;
        $LJ::AUTH_EXISTS = sub {
            my $user = shift;
            my $rec = LJ::LDAP::load_ldap_user($user);
            return $rec ? $rec : undef;
        };
    }

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    my $lu;
    if (ref $LJ::AUTH_EXISTS eq "CODE" && ($lu = $LJ::AUTH_EXISTS->($user)))
    {
        my $name = ref $lu eq "HASH" ? ($lu->{'nick'} || $lu->{name} || $user) : $user;
        if (LJ::create_account({
            'user' => $user,
            'name' => $name,
            'email' => ref $lu eq "HASH" ? $lu->{email} : "",
            'password' => "",
        }))
        {
            # this should pull from the master, since it was _just_ created
            return $get_user->("master");
        }
    }

    return undef;
}

# <LJFUNC>
# name: LJ::u_equals
# des: Compares two user objects to see if they're the same user.
# args: userobj1, userobj2
# des-userobj1: First user to compare.
# des-userobj2: Second user to compare.
# returns: Boolean, true if userobj1 and userobj2 are defined and have equal userids.
# </LJFUNC>
sub u_equals {
    my ($u1, $u2) = @_;
    return $u1 && $u2 && $u1->{'userid'} == $u2->{'userid'};
}

# <LJFUNC>
# name: LJ::load_userid
# des: Loads a user record given a userid.
# info: From the [dbarg[user]] table.
# args: dbarg?, userid, force?
# des-userid: Userid of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_userid
{
    &nodb;
    my ($userid, $force) = @_;
    return undef unless $userid;

    my $set_req_cache = sub {
        my $u = shift;
        $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u;
        $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u;
        return $u;
    };

    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "userid", $userid);
        return $u unless $u && $use_dbh;

        # set caches since we got a u from the master
        LJ::memcache_set_u($u);
        return $set_req_cache->($u);
    };

    # user is forcing master, return now
    return $get_user->("master") if $force;

    my $u;

    # check process cache
    $u = $LJ::REQ_CACHE_USER_ID{$userid};
    return $u if $u;

    # check memcache
    $u = LJ::memcache_get_u([$userid,"userid:$userid"]);
    return $set_req_cache->($u) if $u;

    # get from master if using memcache
    return $get_user->("master") if @LJ::MEMCACHE_SERVERS;

    # check slave
    $u = $get_user->();
    return $u if $u;

    # if we didn't get a u from the reader, fall back to master
    return $get_user->("master");
}

sub memcache_get_u
{
    my @keys = @_;
    my @ret;
    foreach my $ar (values %{LJ::MemCache::get_multi(@keys) || {}}) {
        my $u = LJ::MemCache::array_to_hash("user", $ar);
        if ($u) {
            bless $u, 'LJ::User';
            push @ret, $u;
        }
    }
    return wantarray ? @ret : $ret[0];
}

sub memcache_set_u
{
    my $u = shift;
    return unless $u;
    my $expire = time() + 1800;
    my $ar = LJ::MemCache::hash_to_array("user", $u);
    return unless $ar;
    LJ::MemCache::set([$u->{'userid'}, "userid:$u->{'userid'}"], $ar, $expire);
    LJ::MemCache::set("uidof:$u->{user}", $u->{userid});
}

# <LJFUNC>
# name: LJ::get_bio
# des: gets a user bio, from db or memcache
# args: u, force
# des-force: true to get data from cluster master
# returns: string
# </LJFUNC>
sub get_bio {
    my ($u, $force) = @_;
    return unless $u && $u->{'has_bio'} eq "Y";

    my $bio;

    my $memkey = [$u->{'userid'}, "bio:$u->{'userid'}"];
    unless ($force) {
        my $bio = LJ::MemCache::get($memkey);
        return $bio if defined $bio;
    }

    # not in memcache, fall back to disk
    my $db = @LJ::MEMCACHE_SERVERS || $force ?
      LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
    $bio = $db->selectrow_array("SELECT bio FROM userbio WHERE userid=?",
                                undef, $u->{'userid'});

    # set in memcache
    LJ::MemCache::add($memkey, $bio);

    return $bio;
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
    if (isu($user)) {
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
    &nodb;
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

# $dom: 'L' == log, 'T' == talk, 'M' == modlog, 'S' == session,
#       'R' == memory (remembrance), 'K' == keyword id,
#       'P' == phone post, 'C' == pending comment
sub alloc_user_counter
{
    my ($u, $dom, $opts) = @_;
    $opts ||= {};

    ##################################################################
    # IF YOU UPDATE THIS MAKE SURE YOU ADD INITIALIZATION CODE BELOW #
    return undef unless $dom =~ /^[LTMPSRKCO]$/;                     #
    ##################################################################

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $newmax;
    my $uid = $u->{'userid'}+0;
    return undef unless $uid;
    my $memkey = [$uid, "auc:$uid:$dom"];

    # in a master-master DB cluster we need to be careful that in
    # an automatic failover case where one cluster is slightly behind
    # that the same counter ID isn't handed out twice.  use memcache
    # as a sanity check to record/check latest number handed out.
    my $memmax = int(LJ::MemCache::get($memkey) || 0);

    my $rs = $dbh->do("UPDATE usercounter SET max=LAST_INSERT_ID(GREATEST(max,$memmax)+1) ".
                      "WHERE journalid=? AND area=?", undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

        # if we've got a supplied callback, lets check the counter
        # number for consistency.  If it fails our test, wipe
        # the counter row and start over, initializing a new one.
        # callbacks should return true to signal 'all is well.'
        if ($opts->{callback} && ref $opts->{callback} eq 'CODE') {
            my $rv = 0;
            eval { $rv = $opts->{callback}->($u, $newmax) };
            if ($@ or ! $rv) {
                $dbh->do("DELETE FROM usercounter WHERE " .
                         "journalid=? AND area=?", undef, $uid, $dom);
                return LJ::alloc_user_counter($u, $dom);
            }
        }

        LJ::MemCache::set($memkey, $newmax);
        return $newmax;
    }

    if ($opts->{recurse}) {
        # We shouldn't ever get here if all is right with the world.
        return undef;
    }

    my $qry_map = {
        # for entries:
        'log'         => "SELECT MAX(jitemid) FROM log2     WHERE journalid=?",
        'logtext'     => "SELECT MAX(jitemid) FROM logtext2 WHERE journalid=?",
        'talk_nodeid' => "SELECT MAX(nodeid)  FROM talk2    WHERE nodetype='L' AND journalid=?",
        # for comments:
        'talk'     => "SELECT MAX(jtalkid) FROM talk2     WHERE journalid=?",
        'talktext' => "SELECT MAX(jtalkid) FROM talktext2 WHERE journalid=?",
    };

    my $consider = sub {
        my @tables = @_;
        foreach my $t (@tables) {
            my $res = $u->selectrow_array($qry_map->{$t}, undef, $uid);
            $newmax = $res if $res > $newmax;
        }
    };

    # Make sure the counter table is populated for this uid/dom.
    if ($dom eq "L") {
        # back in the ol' days IDs were reused (because of MyISAM)
        # so now we're extra careful not to reuse a number that has
        # foreign junk "attached".  turns out people like to delete
        # each entry by hand, but we do lazy deletes that are often
        # too lazy and a user can see old stuff come back alive
        $consider->("log", "logtext", "talk_nodeid");
    } elsif ($dom eq "T") {
        # just paranoia, not as bad as above.  don't think we've ever
        # run into cases of talktext without a talk, but who knows.
        # can't hurt.
        $consider->("talk", "talktext");
    } elsif ($dom eq "M") {
        $newmax = $u->selectrow_array("SELECT MAX(modid) FROM modlog WHERE journalid=?",
                                      undef, $uid);
    } elsif ($dom eq "S") {
        $newmax = $u->selectrow_array("SELECT MAX(sessid) FROM sessions WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "R") {
        $newmax = $u->selectrow_array("SELECT MAX(memid) FROM memorable2 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "K") {
        $newmax = $u->selectrow_array("SELECT MAX(kwid) FROM userkeywords WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "P") {
        my $userblobmax = $u->selectrow_array("SELECT MAX(blobid) FROM userblob WHERE journalid=? AND domain=?",
                                              undef, $uid, LJ::get_blob_domainid("phonepost"));
        my $ppemax = $u->selectrow_array("SELECT MAX(blobid) FROM phonepostentry WHERE userid=?",
                                         undef, $uid);
        $newmax = ($ppemax > $userblobmax) ? $ppemax : $userblobmax;
    } elsif ($dom eq "C") {
        $newmax = $u->selectrow_array("SELECT MAX(pendid) FROM pendcomments WHERE jid=?",
                                      undef, $uid);
    } elsif ($dom eq "O") {
        $newmax = $u->selectrow_array("SELECT MAX(pboxid) FROM portal_config WHERE userid=?",
                                      undef, $uid);
    } else {
        die "No user counter initializer defined for area '$dom'.\n";
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO usercounter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return undef;

    # The 2nd invocation of the alloc_user_counter sub should do the
    # intended incrementing.
    return LJ::alloc_user_counter($u, $dom, { recurse => 1 });
}

# <LJFUNC>
# name: LJ::make_user_active
# des:  Record user activity per cluster to
#       make per-activity cluster stats easier.
# args: userobj, type
# arg-userid: source userobj ref
# arg-type: currently unused
# </LJFUNC>
sub mark_user_active {
    my ($u, $type) = @_;  # not currently using type
    return 0 unless $u;   # do not auto-vivify $u
    my $uid = $u->{userid};
    return 0 unless $uid && $u->{clusterid};

    # Update the clustertrack table, but not if we've done it for this
    # user in the last hour.  if no memcache servers are configured
    # we don't do the optimization and just always log the activity info
    if (@LJ::MEMCACHE_SERVERS == 0 ||
        LJ::MemCache::add("rate:tracked:$uid", 1, 3600)) {

        return 0 unless $u->writer;
        $u->do("REPLACE INTO clustertrack2 SET ".
               "userid=?, timeactive=?, clusterid=?", undef,
               $uid, time(), $u->{clusterid}) or return 0;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::infohistory_add
# des: Add a line of text to the infohistory table for an account.
# args: uuid, what, value, other?
# des-uuid: User id or user object to insert infohistory for.
# des-what: What type of history being inserted (15 chars max).
# des-value: Value for the item (255 chars max).
# des-other: Extra information (30 chars max).
# returns: 1 on success, 0 on error.
# </LJFUNC>
sub infohistory_add {
    my ($uuid, $what, $value, $other) = @_;
    $uuid = LJ::want_userid($uuid);
    return unless $uuid && $what && $value;

    # get writer and insert
    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO infohistory (userid, what, timechange, oldvalue, other) VALUES (?, ?, NOW(), ?, ?)",
             undef, $uuid, $what, $value, $other);
    return $dbh->err ? 0 : 1;
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
    my %multihomed;  # { $propid => $value }

    foreach $propname (keys %$hash) {
        my $p = LJ::get_prop("user", $propname) or
            die "Invalid userprop $propname passed to LJ::set_userprop.";
        if ($p->{multihomed}) {
            # collect into array for later handling
            $multihomed{$p->{id}} = $hash->{$propname};
            next;
        }
        my $table = $p->{'indexed'} ? "userprop" : "userproplite";
        if ($p->{datatype} eq 'blobchar') {
            $table = 'userpropblob';
        }
        elsif ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
            $table = "userproplite2";
        }
        unless ($memonly) {
            my $db = $action{$table}->{'db'} ||= (
                $table !~ m{userprop(lite2|blob)}
                    ? LJ::get_db_writer()
                    : $u->writer );
            return 0 unless $db;
        }
        $value = $hash->{$propname};
        if (defined $value && $value) {
            push @{$action{$table}->{"replace"}}, [ $p->{'id'}, $value ];
        } else {
            push @{$action{$table}->{"delete"}}, $p->{'id'};
        }
    }

    my $expire = time() + 3600*24;
    foreach my $table (keys %action) {
        my $db = $action{$table}->{'db'};
        if (my $list = $action{$table}->{"replace"}) {
            if ($db) {
                my $vals = join(',', map { "($userid,$_->[0]," . $db->quote($_->[1]) . ")" } @$list);
                $db->do("REPLACE INTO $table (userid, upropid, value) VALUES $vals");
            }
            LJ::MemCache::set([$userid,"uprop:$userid:$_->[0]"], $_->[1], $expire) foreach (@$list);
        }
        if (my $list = $action{$table}->{"delete"}) {
            if ($db) {
                my $in = join(',', @$list);
                $db->do("DELETE FROM $table WHERE userid=$userid AND upropid IN ($in)");
            }
            LJ::MemCache::set([$userid,"uprop:$userid:$_"], "", $expire) foreach (@$list);
        }
    }

    # if we had any multihomed props, set them here
    if (%multihomed) {
        my $dbh = LJ::get_db_writer();
        return 0 unless $dbh && $u->writer;
        while (my ($propid, $pvalue) = each %multihomed) {
            if (defined $pvalue && $pvalue) {
                # replace data into master
                $dbh->do("REPLACE INTO userprop VALUES (?, ?, ?)",
                         undef, $userid, $propid, $pvalue);
            } else {
                # delete data from master, but keep in cluster
                $dbh->do("DELETE FROM userprop WHERE userid = ? AND upropid = ?",
                         undef, $userid, $propid);
            }

            # fail out?
            return 0 if $dbh->err;

            # put data in cluster
            $pvalue ||= '';
            $u->do("REPLACE INTO userproplite2 VALUES (?, ?, ?)",
                   undef, $userid, $propid, $pvalue);
            return 0 if $u->err;

            # set memcache
            LJ::MemCache::set([$userid,"uprop:$userid:$propid"], $pvalue, $expire);
        }
    }

    return 1;
}

# <LJFUNC>
# name: LJ::get_shared_journals
# des: Gets an array of shared journals a user has access to.
# returns: An array of shared journals.
# args: u
# </LJFUNC>
sub get_shared_journals
{
    my $u = shift;
    my $ids = LJ::load_rel_target($u, 'A') || [];

    # have to get usernames;
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);
    return sort map { $_->{'user'} } values %users;
}

# <LJFUNC>
# class: component
# name: LJ::ljuser
# des: Make link to userinfo/journal of user.
# info: Returns the HTML for a userinfo/journal link pair for a given user
#       name, just like LJUSER does in BML.  This is for files like cleanhtml.pl
#       and ljpoll.pl which need this functionality too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to, or user hashref.
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full userinfo.   Key 'type' when 'C' makes
#           a community link, when 'Y' makes a syndicated account link,
#           when 'N' makes a news account link, otherwise makes a user account
#           link. If user parameter is a hashref, its 'journaltype' overrides
#           this 'type'.  Key 'del', when true, makes a tag for a deleted user.
#           If user parameter is a hashref, its 'statusvis' overrides 'del'.
#           Key 'no_follow', when true, disables traversal of renamed users.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser
{
    my $user = shift;
    my $opts = shift;
    my $u;
    my $do_dynamic = $LJ::DYNAMIC_LJUSER || ($user =~ /^ext_/);
    if ($do_dynamic && ! isu($user) && ! $opts->{'type'}) {
        # Try to automatically pick the user type, but still
        # make something if we can't (user doesn't exist?)
        $user = LJ::load_user($user) || $user;

        my $hops = 0;

        # Traverse the renames to the final journal
        while (ref $user and $user->{'journaltype'} eq 'R'
               and ! $opts->{'no_follow'} && $hops++ < 5) {

            LJ::load_user_props($user, 'renamedto');
            last unless length $user->{'renamedto'};
            $user = LJ::load_user($user->{'renamedto'});
        }
    }

    if (isu($user)) {
        $u = $user;
        $opts->{'type'} = $user->{'journaltype'};
        # Mark accounts as deleted that aren't visible, memorial, or locked
        $opts->{'del'} = $user->{'statusvis'} ne 'V' &&
            $user->{'statusvis'} ne 'M' &&
            $user->{'statusvis'} ne 'L';
        $user = $user->{'user'};
    }
    my $andfull = $opts->{'full'} ? "&amp;mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';
    my $make_tag = sub {
        my ($fil, $dir, $x, $y) = @_;
        $y ||= $x;  # make square if only one dimension given

        return "<span class='ljuser' style='white-space: nowrap;$strike'><a href='$LJ::SITEROOT/userinfo.bml?user=$user$andfull'><img src='$img/$fil' alt='[info]' width='$x' height='$y' style='vertical-align: bottom; border: 0;' /></a><a href='$LJ::SITEROOT/$dir/$user/'><b>$user</b></a></span>";
    };

    if ($opts->{'type'} eq 'C') {
        return $make_tag->('community.gif', 'community', 16);
    } elsif ($opts->{'type'} eq 'Y') {
        return $make_tag->('syndicated.gif', 'users', 16);
    } elsif ($opts->{'type'} eq 'N') {
        return $make_tag->('newsinfo.gif', 'users', 16);
    } elsif ($opts->{'type'} eq 'I') {
        return $u->ljuser_display($opts);
    } else {
        return $make_tag->('userinfo.gif', 'users', 17);
    }
}

sub update_user
{
    my ($arg, $ref) = @_;
    my @uid;

    if (ref $arg eq "ARRAY") {
        @uid = @$arg;
    } else {
        @uid = want_userid($arg);
    }
    @uid = grep { $_ } map { $_ + 0 } @uid;
    return 0 unless @uid;

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
        my $where = @uid == 1 ? "userid=$uid[0]" : "userid IN (@uid)";
        $dbh->do("UPDATE user SET @sets WHERE $where", undef,
                 @bindparams);
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        LJ::memcache_kill($_, "userid") foreach @uid;
    }
    return 1;
}

# <LJFUNC>
# name: LJ::get_timezone
# des: Gets the timezone offset for the user.
# args: u, offsetref, fakedref
# des-u: user object.
# des-offsetref: reference to scalar to hold timezone offset;
# des-fakedref: reference to scalar to hold whether this timezone was
#               faked.  0 if it is the timezone specified by the user (not supported yet).
# returns: nonzero if successful.
# </LJFUNC>
sub get_timezone {
    my ($u, $offsetref, $fakedref) = @_;

    # we currently don't support timezones,
    # but when we do this will be the function to modify.

    my $offset;

    my $dbcr = LJ::get_cluster_def_reader($u);
    return 0 unless $dbcr;

    # we guess their current timezone's offset
    # by comparing the gmtime of their last post
    # with the time they specified on that post.

    # grab the times on the last post that wasn't backdated.
    # (backdated is rlogtime == $LJ::EndOfTime)
    if (my $last_row = $dbcr->selectrow_hashref(
        qq{
            SELECT rlogtime, eventtime
            FROM log2
            WHERE journalid = ? AND rlogtime <> ?
            ORDER BY rlogtime LIMIT 1
        }, undef, $u->{userid}, $LJ::EndOfTime)) {
        my $logtime = $LJ::EndOfTime - $last_row->{'rlogtime'};
        my $eventtime = LJ::mysqldate_to_time($last_row->{'eventtime'}, 1);
        my $hourdiff = ($eventtime - $logtime) / 3600;

        # if they're up to a quarter hour behind, round up.
        $$offsetref = $hourdiff > 0 ? int($hourdiff + 0.25) : int($hourdiff - 0.25);
    }

    # until we store real timezones, the timezone is always faked.
    $$fakedref = 1 if $fakedref;

    return 1;
}

# returns undef on error, or otherwise arrayref of arrayrefs,
# each of format [ year, month, day, count ] for all days with
# non-zero count.  examples:
#  [ [ 2003, 6, 5, 3 ], [ 2003, 6, 8, 4 ], ... ]
#
sub get_daycounts
{
    my ($u, $remote, $not_memcache) = @_;
    # NOTE: $remote not yet used.  one of the oldest LJ shortcomings is that
    # it's public how many entries users have per-day, even if the entries
    # are protected.  we'll be fixing that with a new table, but first
    # we're moving everything to this API.

    my $uid = LJ::want_userid($u) or return undef;

    my @days;
    my $memkey = [$uid,"dayct:$uid"];
    unless ($not_memcache) {
        my $list = LJ::MemCache::get($memkey);
        return $list if $list;
    }

    my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) ".
                             "FROM log2 WHERE journalid=? GROUP BY 1, 2, 3");
    $sth->execute($uid);
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        # we force each number from string scalars (from DBI) to int scalars,
        # so they store smaller in memcache
        push @days, [ int($y), int($m), int($d), int($c) ];
    }
    LJ::MemCache::add($memkey, \@days);
    return \@days;
}

# <LJFUNC>
# name: LJ::modify_caps
# des: Given a list of caps to add and caps to remove, updates a user's caps
# args: uuid, cap_add, cap_del, res
# arg-cap_add: arrayref of bit numbers to turn on
# arg-cap_del: arrayref of bit numbers to turn off
# arg-res: hashref returned from 'modify_caps' hook
# returns: updated u object, retrieved from $dbh, then 'caps' key modified
#          otherwise, returns 0 unless all  hooks run properly
# </LJFUNC>
sub modify_caps {
    my ($argu, $cap_add, $cap_del, $res) = @_;
    my $userid = LJ::want_userid($argu);
    return undef unless $userid;

    $cap_add ||= [];
    $cap_del ||= [];
    my %cap_add_mod = ();
    my %cap_del_mod = ();

    # convert capnames to bit numbers
    if (LJ::are_hooks("get_cap_bit")) {
        foreach my $bit (@$cap_add, @$cap_del) {
            next if $bit =~ /^\d+$/;

            # bit is a magical reference into the array
            $bit = LJ::run_hook("get_cap_bit", $bit);
        }
    }

    # get a u object directly from the db
    my $u = LJ::load_userid($userid, "force");

    # add new caps
    my $newcaps = int($u->{'caps'});
    foreach (@$cap_add) {
        my $cap = 1 << $_;

        # about to turn bit on, is currently off?
        $cap_add_mod{$_} = 1 unless $newcaps & $cap;
        $newcaps |= $cap;
    }

    # remove deleted caps
    foreach (@$cap_del) {
        my $cap = 1 << $_;

        # about to turn bit off, is it currently on?
        $cap_del_mod{$_} = 1 if $newcaps & $cap;
        $newcaps &= ~$cap;
    }

    # run hooks for modified bits
    if (LJ::are_hooks("modify_caps")) {
        $res = LJ::run_hook("modify_caps",
                            { 'u' => $u,
                              'newcaps' => $newcaps,
                              'oldcaps' => $u->{'caps'},
                              'cap_on_req'  => { map { $_ => 1 } @$cap_add },
                              'cap_off_req' => { map { $_ => 1 } @$cap_del },
                              'cap_on_mod'  => \%cap_add_mod,
                              'cap_off_mod' => \%cap_del_mod,
                          });

        # hook should return a status code
        return undef unless defined $res;
    }

    # update user row
    LJ::update_user($u, { 'caps' => $newcaps });

    return $u;
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

    return 0 unless $u->writer;

    my $rp = LJ::get_prop("rate", $ratename);
    return 0 unless $rp;

    my $now = time();
    my $beforeperiod = $now - $rateperiod;

    # delete inapplicable stuff (or some of it)
    $u->do("DELETE FROM ratelog WHERE userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
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
    $u->do("INSERT INTO ratelog (userid, rlid, evttime, ip, quantity) VALUES ".
           "($u->{'userid'}, $rp->{'id'}, $now, INET_ATON($ip), $count)");
    return 1;
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

# <LJFUNC>
# name: LJ::userpic_count
# des: Gets a count of userpics for a given user
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
# also supports depreciated old method of an array ref of picids
# </LJFUNC>
sub userpic_count {
    my $u = shift or return undef;

    if ($u->{'dversion'} > 6) {
        my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
        return $dbcr->selectrow_array("SELECT COUNT(*) FROM userpic2 " .
                                      "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
    }

    my $dbh = LJ::get_db_writer() or return undef;
    return $dbh->selectrow_array("SELECT COUNT(*) FROM userpic " .
                                 "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
}

# <LJFUNC>
# name: LJ::_friends_do
# des: Runs given sql, then deletes the given userid's friends from memcache
# args: uuserid, sql, args
# des-uuserid: a userid or u object
# des-sql: sql to run via $dbh->do()
# des-args: a list of arguments to pass use via: $dbh->do($sql, undef, @args)
# returns: return false on error
# </LJFUNC>
sub _friends_do {
    my ($uuid, $sql, @args) = @_;
    my $uid = want_userid($uuid);
    return undef unless $uid && $sql;

    my $dbh = LJ::get_db_writer() or return 0;

    my $ret = $dbh->do($sql, undef, @args);
    return 0 if $dbh->err;

    LJ::memcache_kill($uid, "friends");

    # pass $uuid in case it's a $u object which mark_dirty wants
    LJ::mark_dirty($uuid, "friends");

    return 1;
}

# <LJFUNC>
# name: LJ::add_friend
# des: Simple interface to add a friend edge.
# args: uuid, to_add, opts?
# des-to_add: a single uuid or an arrayref of uuids to add (befriendees)
# des-opts: hashref; 'defaultview' key means add target uuids to $uuid's Default View friends group
# returns: boolean; 1 on success (or already friend), 0 on failure (bogus args)
# </LJFUNC>
sub add_friend
{
    &nodb;
    my ($userid, $to_add, $opts) = @_;

    $userid = LJ::want_userid($userid);
    return 0 unless $userid;

    my @add_ids = ref $to_add eq 'ARRAY' ? map { LJ::want_userid($_) } @$to_add : ( LJ::want_userid($to_add) );
    return 0 unless @add_ids;

    my $dbh = LJ::get_db_writer();

    my $black = LJ::color_todb("#000000");
    my $white = LJ::color_todb("#ffffff");

    my $groupmask = 1;
    if ($opts->{'defaultview'}) {
        # TAG:FR:ljlib:add_friend_getdefviewmask
        my $group = LJ::get_friend_group($userid, { name => 'Default View' });
        my $grp = $group ? $group->{groupnum}+0 : 0;
        $groupmask |= (1 << $grp) if $grp;
    }

    # TAG:FR:ljlib:add_friend
    my $bind = join(",", map { "(?,?,?,?,?)" } @add_ids);
    my @vals = map { $userid, $_, $black, $white, $groupmask } @add_ids;

    my $res = LJ::_friends_do
        ($userid, "INSERT IGNORE INTO friends (userid, friendid, fgcolor, bgcolor, groupmask) VALUES $bind", @vals);

    # delete friend-of memcache keys for anyone who was added
    foreach (@add_ids) {
        LJ::MemCache::delete([ $userid, "frgmask:$userid:$_" ]);
        LJ::memcache_kill($_, 'friendofs');
    }

    return $res;
}

# <LJFUNC>
# name: LJ::remove_friend
# args: uuid, to_del
# des-to_del: a single uuid or an arrayref of uuids to remove
# </LJFUNC>
sub remove_friend
{
    my ($userid, $to_del) = @_;

    $userid = LJ::want_userid($userid);
    return undef unless $userid;

    my @del_ids = ref $to_del eq 'ARRAY' ? map { LJ::want_userid($_) } @$to_del : ( LJ::want_userid($to_del) );
    return 0 unless @del_ids;

    my $bind = join(",", map { "?" } @del_ids);
    my $res = LJ::_friends_do($userid, "DELETE FROM friends WHERE userid=? AND friendid IN ($bind)",
                              $userid, @del_ids);

    # delete friend-of memcache keys for anyone who was removed
    foreach my $fid (@del_ids) {
        LJ::MemCache::delete([ $userid, "frgmask:$userid:$fid" ]);
        LJ::memcache_kill($fid, 'friendofs');
    }

    return $res;
}
*delete_friend_edge = \&LJ::remove_friend;

# <LJFUNC>
# name: LJ::get_friends
# des: Returns friends rows for a given user.
# args: uuserid, mask?, memcache_only?, force?
# des-uuserid: a userid or u object
# des-mask: a security mask to filter on
# des-memcache_only: flag, set to only return data from memcache
# des-force: flag, set to ignore memcache and always hit db
# returns: hashref; keys = friend userids
#                   values = hashrefs of 'friends' columns and their values
# </LJFUNC>
sub get_friends {
    # TAG:FR:ljlib:get_friends
    my ($uuid, $mask, $memcache_only, $force) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid;
    return undef if $LJ::FORCE_EMPTY_FRIENDS{$userid};

    # memcache data version
    my $ver = 1;

    my $packfmt = "NH6H6NC";
    my $packlen = 15;  # bytes

    my @cols = qw(friendid fgcolor bgcolor groupmask showbydefault);

    # first, check memcache
    my $memkey = [$userid, "friends:$userid"];

    unless ($force) {
        my $memfriends = LJ::MemCache::get($memkey);
        if ($memfriends) {
            my %friends; # rows to be returned

            # first byte of object is data version
            # only version 1 is meaningful right now
            my $memver = substr($memfriends, 0, 1, '');
            return undef unless $memver == $ver;

            # get each $packlen-byte row
            while (length($memfriends) >= $packlen) {
                my @row = unpack($packfmt, substr($memfriends, 0, $packlen, ''));

                # don't add into %friends hash if groupmask doesn't match
                next if $mask && ! ($row[3]+0 & $mask+0);

                # add "#" to beginning of colors
                $row[$_] = "\#$row[$_]" foreach 1..2;

                # turn unpacked row into hashref
                my $fid = $row[0];
                my $idx = 1;
                foreach my $col (@cols[1..$#cols]) {
                    $friends{$fid}->{$col} = $row[$idx];
                    $idx++;
                }
            }

            # got from memcache, return
            return \%friends;
        }
    }
    return {} if $memcache_only; # no friends

    # nothing from memcache, select all rows from the
    # database and insert those into memcache
    # then return rows that matched the given groupmask

    my $mempack = $ver; # full packed string to insert into memcache, byte 1 is dversion
    my %friends;        # friends object to be returned, all groupmasks match
    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare("SELECT friendid, fgcolor, bgcolor, groupmask, showbydefault " .
                            "FROM friends WHERE userid=?");
    $sth->execute($userid);
    die $dbh->errstr if $dbh->err;
    while (my @row = $sth->fetchrow_array) {

        # convert color columns to hex
        $row[$_] = sprintf("%06x", $row[$_]) foreach 1..2;

        $mempack .= pack($packfmt, @row);

        # unless groupmask matches, skip adding to %friends
        next if $mask && ! ($row[3]+0 & $mask+0);

        # add "#" to beginning of colors
        $row[$_] = "\#$row[$_]" foreach 1..2;

        my $fid = $row[0];
        my $idx = 1;
        foreach my $col (@cols[1..$#cols]) {
            $friends{$fid}->{$col} = $row[$idx];
            $idx++;
        }
    }

    LJ::MemCache::add($memkey, $mempack);

    return \%friends;
}

# <LJFUNC>
# name: LJ::get_friendofs
# des: Returns userids of friendofs for a given user.
# args: uuserid, opts?
# des-opts: options hash, keys: 'force' => don't check memcache
# returns: userid for friendofs
# </LJFUNC>
sub get_friendofs {
    # TAG:FR:ljlib:get_friends
    my ($uuid, $opts) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid;

    # first, check memcache
    my $memkey = [$userid, "friendofs:$userid"];

    unless ($opts->{force}) {
        my $memfriendofs = LJ::MemCache::get($memkey);
        return @$memfriendofs if $memfriendofs;
    }

    # nothing from memcache, select all rows from the
    # database and insert those into memcache

    my $dbh = LJ::get_db_writer();
    my $limit = $opts->{force} ? '' : " LIMIT " . ($LJ::MAX_FRIENDOF_LOAD+1);
    my $friendofs = $dbh->selectcol_arrayref
        ("SELECT userid FROM friends WHERE friendid=?$limit",
         undef, $userid) || [];
    die $dbh->errstr if $dbh->err;

    LJ::MemCache::add($memkey, $friendofs);

    return @$friendofs;
}


# <LJFUNC>
# name: LJ::get_friend_group
# des: Returns friendgroup row(s) for a given user.
# args: uuserid, opt?
# des-uuserid: a userid or u object
# des-opt: a hashref with keys: 'bit' => bit number of group to return
#                               'name' => name of group to return
# returns: hashref; if bit/name are specified, returns hashref with keys being
#                   friendgroup rows, or undef if the group wasn't found.
#
#                   otherwise, returns hashref of all group rows with keys being
#                   group bit numbers and values being row col => val hashrefs
# </LJFUNC>
sub get_friend_group {
    my ($uuid, $opt) = @_;
    my $u = LJ::want_user($uuid);
    return undef unless $u;
    my $uid = $u->{userid};

    # data version number
    my $ver = 1;

    # sanity check bitnum
    delete $opt->{'bit'} if
        $opt->{'bit'} > 31 || $opt->{'bit'} < 0;

    my $fg;
    my $find_grp = sub {

        # $fg format:
        # [ version, [userid, bitnum, name, sortorder, public], [...], ... ]

        my $memver = shift @$fg;
        return undef unless $memver == $ver;

        # bit number was specified
        if ($opt->{'bit'}) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash("fgrp", [$memver, @$_])
                    if $_->[1] == $opt->{'bit'};
            }
            return undef;
        }

        # group name was specified
        if ($opt->{'name'}) {
            foreach (@$fg) {
                return LJ::MemCache::array_to_hash("fgrp", [$memver, @$_])
                    if lc($_->[2]) eq lc($opt->{'name'});
            }
            return undef;
        }

        # no arg, return entire object
        return { map { $_->[1] => LJ::MemCache::array_to_hash("fgrp", [$memver, @$_]) } @$fg };
    };

    # check memcache
    my $memkey = [$uid, "fgrp:$uid"];
    $fg = LJ::MemCache::get($memkey);
    return $find_grp->() if $fg;

    # check database
    $fg = [$ver];
    my ($db, $fgtable) = $u->{dversion} > 5 ?
                         (LJ::get_cluster_def_reader($u), 'friendgroup2') : # if dversion is 6+, use definitive reader
                         (LJ::get_db_writer(), 'friendgroup');              # else, use regular db writer
    return undef unless $db;

    my $sth = $db->prepare("SELECT userid, groupnum, groupname, sortorder, is_public " .
                           "FROM $fgtable WHERE userid=?");
    $sth->execute($uid);
    return LJ::error($db) if $db->err;

    my @row;
    push @$fg, [ @row ] while @row = $sth->fetchrow_array;

    # set in memcache
    LJ::MemCache::set($memkey, $fg);

    return $find_grp->();
}

# <LJFUNC>
# name: LJ::fill_groups_xmlrpc
# des: Fills a hashref (presumably to be sent to an XMLRPC client, EG fotobilder)
#      with user friend group information
# args: u, ret
# des-ret: a response hashref to fill with friend group data
# returns: undef if called incorrectly, 1 otherwise
# </LJFUNC>
sub fill_groups_xmlrpc {
    my ($u, $ret) = @_;
    return undef unless ref $u && ref $ret;

    # layer on friend group information in the following format:
    #
    # grp:1 => 'mygroup',
    # ...
    # grp:30 => 'anothergroup',
    #
    # grpu:whitaker => '0,1,2,3,4',
    # grpu:test => '0',

    my $grp = LJ::get_friend_group($u) || {};

    $ret->{"grp:0"} = "_all_";
    foreach my $bit (1..30) {
        next unless my $g = $grp->{$bit};
        $ret->{"grp:$bit"} = $g->{groupname};
    }

    my $fr = LJ::get_friends($u) || {};
    my $users = LJ::load_userids(keys %$fr);
    while (my ($fid, $f) = each %$fr) {
        my $u = $users->{$fid};
        next unless $u->{journaltype} =~ /[PS]/;

        my $fname = $u->{user};
        $ret->{"grpu:$fid:$fname"} =
            join(",", 0, grep { $grp->{$_} && $f->{groupmask} & 1 << $_ } 1..30);
    }

    return 1;
}

# <LJFUNC>
# name: LJ::mark_dirty
# des: Marks a given user as being $what type of dirty
# args: u, what
# des-what: type of dirty being marked (EG 'friends')
# returns: 1
# </LJFUNC>
sub mark_dirty {
    my ($uuserid, $what) = @_;

    my $userid = LJ::want_userid($uuserid);
    return 1 if $LJ::REQ_CACHE_DIRTY{$what}->{$userid};

    my $u = LJ::want_user($userid);

    # friends dirtiness is only necessary to track
    # if we're exchange XMLRPC with fotobilder
    if ($what eq 'friends' && $LJ::FB_SITEROOT) {
        push @LJ::CLEANUP_HANDLERS, sub {
            my $res = LJ::cmd_buffer_add($u->{clusterid}, $u->{userid}, 'dirty', { what => 'friends' });
            };
    } else {
        return 1;
    }

    $LJ::REQ_CACHE_DIRTY{$what}->{$userid}++;

    return 1;
}

# <LJFUNC>
# name: LJ::memcache_kill
# des: Kills a memcache entry, given a userid and type
# args: uuserid, type
# des-uuserid: a userid or u object
# des-args: memcache key type, will be used as "$type:$userid"
# returns: results of LJ::MemCache::delete
# </LJFUNC>
sub memcache_kill {
    my ($uuid, $type) = @_;
    my $userid = want_userid($uuid);
    return undef unless $userid && $type;

    return LJ::MemCache::delete([$userid, "$type:$userid"]);
}

# <LJFUNC>
# name: LJ::delete_all_comments
# des: deletes all comments from a post, permanently, for when a post is deleted
# info: The tables [dbtable[talk2]], [dbtable[talkprop2]], [dbtable[talktext2]],
#       are deleted from, immediately.
# args: u, nodetype, nodeid
# des-nodetype: The thread nodetype (probably 'L' for log items)
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid from the log2 row)
# returns: boolean; success value
# </LJFUNC>
sub delete_all_comments {
    my ($u, $nodetype, $nodeid) = @_;

    my $dbcm = LJ::get_cluster_master($u);
    return 0 unless $dbcm && $u->writer;

    # delete comments
    my ($t, $loop) = (undef, 1);
    my $chunk_size = 200;
    while ($loop &&
           ($t = $dbcm->selectcol_arrayref("SELECT jtalkid FROM talk2 WHERE ".
                                           "nodetype=? AND journalid=? ".
                                           "AND nodeid=? LIMIT $chunk_size", undef,
                                           $nodetype, $u->{'userid'}, $nodeid))
           && $t && @$t)
    {
        my $in = join(',', map { $_+0 } @$t);
        return 1 unless $in;
        foreach my $table (qw(talkprop2 talktext2 talk2)) {
            $u->do("DELETE FROM $table WHERE journalid=? AND jtalkid IN ($in)",
                   undef, $u->{'userid'});
        }
        # decrement memcache
        LJ::MemCache::decr([$u->{'userid'}, "talk2ct:$u->{'userid'}"], scalar(@$t));
        $loop = 0 unless @$t == $chunk_size;
    }
    return 1;

}

# is a user object (at least a hashref)
sub isu { return ref $_[0] && (ref $_[0] eq "LJ::User" ||
                               ref $_[0] eq "HASH" && $_[0]->{userid}); }

1;
