package LJ::Session;
use strict;
use Carp qw(croak);

use constant VERSION => 1;

# NOTE: fields in this object:
#  userid, sessid, exptype, auth, timecreate, timeexpire, ipfixed
# NOTE: do not store any references in the LJ::Session instances because of serialization
# and storage in memcache

sub new {
    my ($class, $u, $sessid) = @_;

}

sub create {
    my ($class, $u, %opts) = @_;

    # validate options
    my $exptype = delete $opts{'exptype'} || "short";
    my $ipfixed = delete $opts{'ipfixed'};   # undef or scalar ipaddress  FIXME: validate
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;

    croak("Invalid options: " . join(", ", keys %opts)) if %opts;


    my $udbh = LJ::get_cluster_master($u);
    return undef unless $udbh;

    # clean up any old, expired sessions they might have (lazy clean)
    $u->do("DELETE FROM sessions WHERE userid=? AND timeexpire < UNIX_TIMESTAMP()",
           undef, $u->{userid});

    my $expsec     = LJ::Session->session_length($exptype);
    my $timeexpire = time() + $expsec;

    my $sess = {
        auth       => LJ::rand_chars(10),
        exptype    => $exptype,
        ipfixed    => $ipfixed,
        timeexpire => $timeexpire,
    };

    my $id = LJ::alloc_user_counter($u, 'S');
    return undef unless $id;

    $u->do("REPLACE INTO sessions (userid, sessid, auth, exptype, ".
           "timecreate, timeexpire, ipfixed) VALUES (?,?,?,?,UNIX_TIMESTAMP(),".
           "?,?)", undef,
           $u->{'userid'}, $id, $sess->{'auth'}, $exptype, $timeexpire, $ipfixed);

    return undef if $u->err;
    $sess->{'sessid'} = $id;
    $sess->{'userid'} = $u->{'userid'};

    # clean up old sessions
    my $old = $udbh->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
                                        "userid=$u->{'userid'} AND ".
                                        "timeexpire < UNIX_TIMESTAMP()");
    $u->kill_sessions(@$old) if $old;

    # mark account as being used
    LJ::mark_user_active($u, 'login');

    return bless $sess;

}

# NOTE: do not store any references in the LJ::Session instances because of serialization
# and storage in memcache
sub owner {
    my $sess = shift;
    return LJ::load_userid($sess->{userid});
}

# based on our type and current expiration length, update this cookie if we need to
sub try_renew {
    my ($sess, $cookies) = @_;

    # only renew long type cookies
    return if $sess->{exptype} ne 'long';

    # how long to live for
    my $u = $sess->owner;
    my $sess_length = LJ::Session->session_length($sess->{exptype});
    my $now = time();
    my $new_expire  = $now + $sess_length;

    # if there is a new session length to be set and the user's db writer is available,
    # go ahead and set the new session expiration in the database. then only update the
    # cookies if the database operation is successful
    if ($sess_length && $sess->{'timeexpire'} - $now < $sess_length/2 &&
        $u->writer && $sess->_dbupdate(timexpire => $new_expire))
    {
        $sess->update_master_cookie;
    }
}

# CLASS METHOD
# call: ( $opts?, @ljmastersession_cookie(s) )
# return value is LJ::Session object if we found one; else undef
# FIXME: document ops
sub session_from_master_cookie {
    my $class = shift;
    my $opts = ref $_[0] ? shift() : {};
    my @cookies = grep { $_ } @_;
    return undef unless @cookies;

    my $errs = delete $opts->{errlist} || [];
    my $tried_fast = delete $opts->{tried_fast} || do { my $foo; \$foo; };
    my $ignore_ip = delete $opts->{ignore_ip} ? 1 : 0;
    croak("Unknown options") if %$opts;
    my $now = time();

    # our return value
    my $sess;

  COOKIE:
    foreach my $sessdata (@cookies) {
        warn "sessdata = $sessdata\n";
        my ($cookie, $gen) = split(m!//!, $sessdata);
        warn "   cookie = $cookie\n";
        warn "   gen = $gen\n";

        my ($version, $userid, $sessid, $auth, $flags);

        my $dest = {
            v => \$version,
            u => \$userid,
            s => \$sessid,
            a => \$auth,
            f => \$flags,
        };

        my $bogus = 0;
        foreach my $var (split /:/, $cookie) {
            if ($var =~ /^(\w)(.+)$/ && $dest->{$1}) {
                ${$dest->{$1}} = $2;
                warn "  cookie attr ($1) = $2\n";
            } else {
                $bogus = 1;
            }
        }

        # must do this first so they can't trick us
        $$tried_fast = 1 if $flags =~ /\.FS\b/;

        next COOKIE if $bogus;

        next COOKIE unless $gen eq $LJ::COOKIE_GEN;

        my $err = sub {
            warn "  ERROR due to: $_[0]";
            $sess = undef;
            push @$errs, "$sessdata: $_[0]";
        };

        # fail unless version matches current
        unless ($version == VERSION) {
            $err->("no ws auth");
            next COOKIE;
        }

        my $u = LJ::load_userid($userid);
        unless ($u) {
            $err->("user doesn't exist");
            next COOKIE;
        }

        # locked accounts can't be logged in
        if ($u->{statusvis} eq 'L') {
            $err->("User account is locked.");
            next COOKIE;
        }

        # try memory
        my $memkey = _memkey($u, $sessid);
        $sess = LJ::MemCache::get($memkey);

        # try master
        unless ($sess) {
            $sess = $u->selectrow_hashref("SELECT userid, sessid, exptype, auth, timecreate, timeexpire, ipfixed " .
                                          "FROM sessions WHERE userid=? AND sessid=?",
                                          undef, $u->{'userid'}, $sessid);

            if ($sess) {
                bless $sess;
                LJ::MemCache::set($memkey, $sess);
            }
        }

        unless ($sess) {
            $err->("Couldn't find session");
            next COOKIE;
        }

        unless ($sess->{auth} eq $auth) {
            $err->("Invald auth");
            next COOKIE;
        }

        if ($sess->{'timeexpire'} < $now) {
            $err->("Invalid auth");
            next COOKIE;
        }

        if ($sess->{'ipfixed'} && ! $ignore_ip) {
            my $remote_ip = $LJ::_XFER_REMOTE_IP || LJ::get_remote_ip();
            if ($sess->{'ipfixed'} ne $remote_ip) {
                $err->("Session wrong IP ($remote_ip != $sess->{ipfixed})");
                next COOKIE;
            }
        }

        last COOKIE;
    }

    return $sess;
}

sub id {
    my $sess = shift;
    return $sess->{sessid};
}

sub ipfixed {
    my $sess = shift;
    return $sess->{ipfixed};
}

sub exptype {
    my $sess = shift;
    return $sess->{exptype};
}

# end a session
sub destroy {
    my $sess = shift;
    my $id = $sess->id;
    my $u = $sess->owner;
    return LJ::Session->destroy_sessions($u, $id);
}

# class method
sub destroy_all_sessions {
    my ($class, $u) = @_;
    return 0 unless $u;

    my $udbh = LJ::get_cluster_master($u)
        or return 0;

    my $sessions = $udbh->selectcol_arrayref("SELECT sessid FROM sessions WHERE ".
                                             "userid=?", undef, $u->{'userid'});

    return LJ::Session->destroy_sessions($u, @$sessions) if @$sessions;
    return 1;
}

# class method
sub destroy_sessions {
    my ($class, $u, @sessids) = @_;

    my $in = join(',', map { $_+0 } @sessids);
    return 1 unless $in;
    my $userid = $u->{'userid'};
    foreach (qw(sessions sessions_data)) {
        $u->do("DELETE FROM $_ WHERE userid=? AND ".
               "sessid IN ($in)", undef, $userid)
            or return 0;   # FIXME: use Error::Strict
    }
    foreach my $id (@sessids) {
        $id += 0;
        LJ::MemCache::delete(_memkey($u, $id));
    }
    return 1;

}

sub clear_master_cookie {
    my ($class) = @_;

    my $domain =
        $LJ::ONLY_USER_VHOSTS ? ($LJ::DOMAIN_WEB || $LJ::DOMAIN) : $LJ::DOMAIN;

    set_cookie(ljmastersession => "",
               domain          => $domain,
               path            => '/',
               delete          => 1);

}

# CLASS method for getting the length of a given session type in seconds
sub session_length {
    my ($class, $exptype) = @_;
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;

    return {
        short => 60*60*24*1.5, # 1.5 days
        long  => 60*60*24*60,  # 60 days
        once  => 60*60*2,      # 2 hours
    }->{$exptype};
}

# returns unix timestamp of expiration
sub expiration_time {
    my $sess = shift;

    # expiration time if we have it,
    return $sess->{timeexpire} if $sess->{timeexpire};

    warn "Had no 'timeexpire' for session.\n";
    return time() + LJ::Session->session_length($sess->{exptype});
}

# sets new ljmastersession cookie given the session object; second parameter is a
# hashref tied to BML's cookies (FIXME: cleaner interface!)
sub update_master_cookie {
    my ($sess) = @_;

    my @expires;
    if ($sess->{exptype} eq 'long') {
        push @expires, expires => $sess->expiration_time;
    }

    my $domain =
        $LJ::ONLY_USER_VHOSTS ? ($LJ::DOMAIN_WEB || $LJ::DOMAIN) : $LJ::DOMAIN;

    set_cookie(ljmastersession => $sess->master_cookie_string,
               domain          => $domain,
               path            => '/',
               http_only       => 1,
               @expires,);

    return;
}

sub master_cookie_string {
    my $sess = shift;

    my $ver = VERSION;
    my $cookie = "v$ver:" .
        "u$sess->{userid}:" .
        "s$sess->{sessid}:" .
        "a$sess->{auth}";

    if ($sess->{flags}) {
        $cookie .= ":f$sess->{flags}";
    }

    $cookie .= "//" . LJ::eurl($LJ::COOKIE_GEN || "");
    return $cookie;
}

# not stored in database, call this before calling to update cookie strings
sub set_flags {
    my ($sess, $flags) = @_;
    $sess->{flags} = $flags;
    return;
}

sub flags {
    my $sess = shift;
    return $sess->{flags};
}

sub set_ipfixed {
    my ($sess, $ip) = @_;
    return $sess->_dbupdate(ipfixed => $ip);
}

sub set_exptype {
    my ($sess, $exptype) = @_;
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;
    return $sess->_dbupdate(exptype => $exptype,
                            timeexpire => time() + LJ::Session->session_length($exptype));
}

# function or instance method.
# FIXME: update the documentation for memkeys
sub _memkey {
    if (@_ == 2) {
        my ($u, $sessid) = @_;
        $sessid += 0;
        return [$u->{'userid'}, "ljms:$u->{'userid'}:$sessid"];
    } else {
        my $sess = shift;
        return [$sess->{'userid'}, "ljms:$sess->{'userid'}:$sess->{sessid}"];
    }
}

sub _dbupdate {
    my ($sess, %changes) = @_;
    my $u = $sess->owner;

    my $n_userid = $sess->{userid} + 0;
    my $n_sessid = $sess->{sessid} + 0;

    my @sets;
    my @values;
    foreach my $k (keys %changes) {
        push @sets, "$k=?";
        push @values, $changes{$k};
    }

    my $rv = $u->do("UPDATE sessions SET " . join(", ", @sets) .
                    " WHERE userid=$n_userid AND sessid=$n_sessid",
                    undef, @values);
    if (!$rv) {
        # FIXME: eventually use Error::Strict here on return
        return 0;
    }

    # update ourself, once db update succeeded
    foreach my $k (keys %changes) {
        $sess->{$k} = $changes{$k};
    }

    LJ::MemCache::delete($sess->_memkey);
    return 1;

}

# FIXME: move this somewhere better
sub set_cookie {
    my ($key, $value, %opts) = @_;

    my $r = eval { Apache->request };
    croak("Can't set cookie in non-web context") unless $r;

    my $http_only = delete $opts{http_only};
    my $domain = delete $opts{domain};
    my $path = delete $opts{path};
    my $expires = delete $opts{expires};
    my $delete = delete $opts{delete};
    croak("Invalid cookie options: " . join(", ", keys %opts)) if %opts;

    # expires can be absolute or relative.  this is gross or clever, your pick.
    $expires += time() if $expires && $expires <= 1135217120;

    if ($delete) {
        # set expires to 5 seconds after 1970.  definitely in the past.
        # so cookie will be deleted.
        $expires = 5 if $delete;
    }

    my $cookiestr = $key . '=' . $value;
    $cookiestr .= '; expires=' . LJ::time_to_cookie($expires) if $expires;
    $cookiestr .= '; domain=' . $domain if $domain;
    $cookiestr .= '; path=' . $path if $path;
    $cookiestr .= '; HttpOnly' if $http_only;

    warn "SETTING-COOKIE: $cookiestr\n";
    $r->err_headers_out->add('Set-Cookie' => $cookiestr);
}

1;
