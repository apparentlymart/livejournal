#!/usr/bin/perl

package LJ::UniqCookie;

use strict;
use Carp qw(croak);
use LJ::TimeUtil;

my %req_cache_uid2uniqs = (); # uid  => [ uniq1, uniq2, ... ]
my %req_cache_uniq2uids = (); # uniq => [  uid1,  uid2, ... ]

# number of uniq cookies to keep in cache + db before being cleaned
my $window_size = 1000;

sub clear_request_cache {
    my $class = shift;

    %req_cache_uid2uniqs = ();
    %req_cache_uniq2uids = ();
}

sub set_request_cache_by_user {
    my $class = shift;
    my ($u_arg, $uniq_list) = @_;

    my $uid = LJ::want_userid($u_arg)
        or croak "invalid user arg: $u_arg";

    croak "invalid uniq list: $uniq_list"
        unless ref $uniq_list eq 'ARRAY';

    return $req_cache_uid2uniqs{$uid} = $uniq_list;
} 

sub get_request_cache_by_user {
    my $class = shift;
    my $u_arg = shift;

    my $uid = LJ::want_userid($u_arg)
        or croak "invalid user arg: $u_arg";

    return $req_cache_uid2uniqs{$uid};
}

sub set_request_cache_by_uniq {
    my $class = shift;
    my ($uniq, $user_list) = @_;

    croak "invalid uniq arg: $uniq"
        unless length $uniq;

    croak "invalid user list: $user_list"
        unless ref $user_list eq 'ARRAY';

    my @userids = ();
    foreach my $u_arg (@$user_list) {
        my $uid = LJ::want_userid($u_arg)
            or croak "invalid arg in user_list: $u_arg";

        push @userids, $uid;
    }

    $req_cache_uniq2uids{$uniq} = \@userids;
} 

sub get_request_cache_by_uniq {
    my $class = shift;
    my $uniq = shift;
    croak "invalid 'uniq' arg: $uniq"
        unless length $uniq;

    return $req_cache_uniq2uids{$uniq};
}

sub delete_memcache_by_user {
    my $class = shift;
    my $u_arg = shift;

    my $uid = LJ::want_userid($u_arg)
        or croak "invalid user arg: $u_arg";

    LJ::MemCache::delete("uid2uniqs:$uid");
}

sub delete_memcache_by_uniq {
    my $class = shift;
    my $uniq = shift;
    croak "invalid 'uniq' arg: $uniq"
        unless length $uniq;

    LJ::MemCache::delete("uniq2uids:$uniq");
}

sub set_memcache_by_user {
    my $class = shift;
    my ($u_arg, $uniq_list) = @_;
    
    my $uid = LJ::want_userid($u_arg)
        or croak "invalid user arg: $u_arg";

    # we store uid => [] and uniq => [], so defined but false 
    # is okay as a value of these memcache keys, but not as part of the key
    my $exptime = 3600;
    LJ::MemCache::set("uid2uniqs:$uid" => $uniq_list, $exptime);
}

sub get_memcache_by_user {
    my $class = shift;
    my $u_arg = shift;

    my $uid = LJ::want_userid($u_arg)
        or die "invalid user arg: $u_arg";

    return LJ::MemCache::get("uid2uniqs:$uid");
}

sub set_memcache_by_uniq {
    my $class = shift;
    my ($uniq, $user_list) = @_;
    
    croak "invalid 'uniq' argument: $uniq"
        unless length $uniq;

    croak "invalid user list: $user_list"
        unless ref $user_list eq 'ARRAY';

    my @userids = ();
    foreach my $u_arg (@$user_list) {
        my $uid = LJ::want_userid($u_arg)
            or croak "invalid arg in user_list: $u_arg";

        push @userids, $uid;
    }

    # we store uid => [] and uniq => [], so defined but false 
    # is okay as a value of these memcache keys, but not as part of the key
    my $exptime = 3600;
    LJ::MemCache::set("uniq2uids:$uniq" => \@userids, $exptime);
}

sub get_memcache_by_uniq {
    my $class = shift;
    my $uniq = shift;
    croak "invalid 'uniq' argument: $uniq"
        unless length $uniq;

    return LJ::MemCache::get("uniq2uids:$uniq");
}

# straight db request instead of loading is used, because we need pure results
# and do not need any uniqs to be cleaned
sub get_shared_uniqs {
    my ($uid, $threshold) = @_;
    $uid ||= 0;
    $threshold ||= 1;

    my $dbr = LJ::get_db_reader();
    my $rows = $dbr->selectall_arrayref(qq{
            SELECT   m2.userid AS uid, 
                     count(m2.uniq) AS qty
            FROM     uniqmap m1 INNER JOIN uniqmap m2 
            USING    (uniq)
            WHERE    m1.userid = ? 
            GROUP BY m2.userid
            HAVING   qty >= ?
            ORDER BY qty DESC
            LIMIT    2000
       }, { Slice => {} },$uid, $threshold);

    return @$rows;
}

sub save_mapping {
    my $class = shift;
    return if $class->is_disabled;

    my ($uniq, $uid_arg) = @_; # no extra parts, only ident
    return unless length $uniq;

    my $uid = LJ::want_userid($uid_arg);
    croak "invalid userid arg: $uid_arg"
        unless $uid;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact uniq master for uniq mapping";

    # allow tests to specify an insertion time callback which specifies 
    # how we calculate insertion times for rows
    my $time_sql = "UNIX_TIMESTAMP()";
    if ($LJ::_T_UNIQCOOKIE_MODTIME_CB) {
        $time_sql = int($LJ::_T_UNIQCOOKIE_MODTIME_CB->($uniq, $uid));
    }

    my $rv = $dbh->do("REPLACE INTO uniqmap SET uniq=?, userid=?, modtime=$time_sql",
             undef, $uniq, $uid);
    die $dbh->errstr if $dbh->err;

    # clear memcache so its next query will reflect our changes
    $class->delete_memcache_by_uniq($uniq);
    $class->delete_memcache_by_user($uid);

    # also clear request cache
    $class->clear_request_cache;

    # we clean on cache misses in ->load_mapping, but we also want
    # to randomly clean on write actions so that we don't end up 
    # with users who write many rows but for some reason never
    # load any rows, and are therefore never cleaned
    if ($class->should_lazy_clean) {
        LJ::no_cache(sub {
            $class->load_mapping( user => $uid );
            # no need for uniq => $uniq case
        });
    }

    return $rv;
}

sub should_lazy_clean {
    my $class = shift;

    # one in 100 times
    my $pct = 0.01;

    if ($LJ::_T_UNIQCOOKIE_LAZY_CLEAN_PCT) {
        $pct = $LJ::_T_UNIQCOOKIE_LAZY_CLEAN_PCT;
    }
    
    return rand() <= $pct;
}

sub is_disabled {
    my $class = shift;

    my $remote = LJ::get_remote();
    my $uniq   = $class->current_uniq;

    return 1 unless $LJ::UNIQ_COOKIES;
    return LJ::conf_test($LJ::DISABLED{uniq_mapping}, $remote, $uniq);
}

sub guess_remote {
    my $class = shift;

    my $uniq = $class->current_uniq;
    return unless $uniq;

    my $uid = $class->load_mapping( uniq => $uniq );
    return LJ::load_userid($uid);
}

# if 'uniq'   passed in, returns mapped userid
# if 'remote' passed in, returns mapped uniq
sub load_mapping {
    my $class = shift;
    return if $class->is_disabled;

    my %opts = @_;

    my $uniq = delete $opts{uniq};
    my $user = delete $opts{user};

    my $ret = sub {
        return wantarray() ? @_ : $_[0];
    };

    if ($user) {
        my $uid = LJ::want_userid($user)
            or croak "invalid user arg: $user";

        return $ret->($class->_load_mapping_uid($uid, %opts));
    }

    if ($uniq) {
        return $ret->($class->_load_mapping_uniq($uniq, %opts));
    }

    croak "must load mapping via 'uniq' or 'user'";
}

sub _load_mapping_uid {
    my $class = shift;
    my $uid = shift;


    # first, check request cache
    my $cache_val = $class->get_request_cache_by_user($uid);
    return @$cache_val if defined $cache_val;
    
    # second, check memcache
    my $memval = $class->get_memcache_by_user($uid);
    if ($memval) {
        $class->set_request_cache_by_user($uid => $memval);
        return @$memval;
    }

    my $dbh = LJ::get_db_writer()
        or die "unable to contact uniq writer";

    my $limit = $window_size + 1;
    my $sth = $dbh->prepare
        ("SELECT uniq, modtime FROM uniqmap WHERE userid=? " . 
         "ORDER BY modtime DESC LIMIT $limit");
    $sth->execute($uid);
    die $dbh->errstr if $dbh->err;

    my (@uniq_list, $min_modtime);
    while (my ($curr_uniq, $modtime) = $sth->fetchrow_array) {
        push @uniq_list, $curr_uniq;
        $min_modtime = $modtime if ! $min_modtime || $modtime < $min_modtime;
    }

    # we got out more rows than we allow after cleaning, so an insert
    # has happened ... we'll clean that now
    my $delete_ct = 0;
    if (@uniq_list >= $limit) {
        $delete_ct = $dbh->do("DELETE FROM uniqmap WHERE userid=? AND modtime<=?", 
                          undef, $uid, $min_modtime);

        @uniq_list = @uniq_list[0..$window_size-1];
    }

    # allow tests to register a callback to determine
    # how many rows were deleted
    if (ref $LJ::_T_UNIQCOOKIE_DELETE_CB) {
        $LJ::_T_UNIQCOOKIE_DELETE_CB->('userid', $delete_ct);
    }


    # now set the value we retrieved in both memcache values
    $class->set_request_cache_by_user($uid => \@uniq_list);
    $class->set_memcache_by_user($uid => \@uniq_list);

    return @uniq_list;
}

sub _load_mapping_uniq {
    my $class = shift;
    my $uniq = shift;

    # first, check request cache
    my $cache_val = $class->get_request_cache_by_uniq($uniq);
    return @$cache_val if defined $cache_val;
    
    # second, check memcache
    my $memval = $class->get_memcache_by_uniq($uniq);
    if ($memval) {
        $class->set_request_cache_by_uniq($uniq => $memval);
        return @$memval;
    }

    my $dbh = LJ::get_db_writer()
        or die "unable to contact uniq reader";

    my $limit = $window_size + 1;
    my $sth = $dbh->prepare
        ("SELECT userid, modtime FROM uniqmap WHERE uniq=? " .
         "ORDER BY modtime DESC LIMIT $limit");
    $sth->execute($uniq);
    die $dbh->errstr if $dbh->err;

    my (@uid_list, $min_modtime);
    while (my ($curr_uid, $modtime) = $sth->fetchrow_array) {
        push @uid_list, $curr_uid;
        $min_modtime = $modtime if ! $min_modtime || $modtime < $min_modtime;
    }

    # we got out more rows than we allow after cleaning, so an insert
    # has happened ... we'll clean that now
    my $delete_ct = 0;
    if (@uid_list >= $limit) {
        $delete_ct = $dbh->do("DELETE FROM uniqmap WHERE uniq=? AND modtime<=?", 
                          undef, $uniq, $min_modtime);

        # trim the cached/returned value as well
        @uid_list = @uid_list[0..$window_size-1];
    }

    # allow tests to register a callback to determine
    # how many rows were deleted
    if (ref $LJ::_T_UNIQCOOKIE_DELETE_CB) {
        $LJ::_T_UNIQCOOKIE_DELETE_CB->('uniq', $delete_ct);
    }

    # now set the value we retrieved in both memcache values
    $class->set_request_cache_by_uniq($uniq => \@uid_list);
    $class->set_memcache_by_uniq($uniq => \@uid_list);

    return @uid_list;
}

sub generate_uniq_ident {
    my $class = shift;

    return LJ::rand_chars(15);
}

###############################################################################
# These methods require web context, they deal with Apache->request and cookies
#

sub ensure_cookie_value {
    my $class = shift;
    return unless LJ::is_web_context();

    return unless LJ::Request->is_inited;

    ## do not set cookie from some domains:
    ##      stat, l-stat
    ##      files, 
    ##      userpic, l-userpic
    ##      ...
    ## these are domains with public, mostly static content.
    ##
    my $domain = LJ::Request->header_in("Host");
    my ($subdomain) = $domain =~ m|^(.+?)\.\Q$LJ::DOMAIN\E|;
    return if $subdomain and $LJ::COOKIE_FREE_DOMAINS{$subdomain};
    return if LJ::Request->uri() =~ m|^/robots.txt|;

    my ($uniq, $uniq_time, $uniq_extra) = $class->parts_from_cookie;

    # set this uniq as our current
    # -- will be overridden later if we generate a new value
    $class->set_current_uniq($uniq);
    
    return;
=head LJSUP-8676: set ljuniq cookie on client side. it allows to cached pages for logged-out users.
    # if no cookie, create one.  if older than a day, revalidate
    my $now = time();
    return if $uniq && $now - $uniq_time < 86400;

    my $setting_new = 0;
    unless ($uniq) {
        $setting_new = 1;
        $uniq = $class->generate_uniq_ident;
    }
    
    my $new_cookie_value = "$uniq:$now";
    my $hook_saved_mapping = 0;
    if (LJ::are_hooks('transform_ljuniq_value')) {
        $new_cookie_value = LJ::run_hook
            ('transform_ljuniq_value',
             { value => $new_cookie_value,
               extra => $uniq_extra,
               hook_saved_mapping => \$hook_saved_mapping});

        # if it changed the actual uniq identifier (first part)
        # then we'll need to 
        $uniq = $class->parts_from_value($new_cookie_value);
    }


    # set this new or transformed uniq in Apache request notes
    $class->set_current_uniq($uniq);

    if ($setting_new && ! $hook_saved_mapping && ! $class->is_disabled) {
        my $remote = LJ::get_remote();
        $class->save_mapping($uniq => $remote) if $remote;
    }

    # set uniq cookies for all cookie_domains
    my @domains = ref $LJ::COOKIE_DOMAIN ? @$LJ::COOKIE_DOMAIN : ($LJ::COOKIE_DOMAIN);
    foreach my $dom (@domains) {
        LJ::Request->err_headers_out->add("Set-Cookie" =>
                                 "ljuniq=$new_cookie_value; " .
                                 "expires=" . LJ::TimeUtil->time_to_cookie($now + 86400*60) . "; " .
                                 ($dom ? "domain=$dom; " : "") . "path=/");
    }
=cut

    return;
}

sub sysban_should_block {
    my $class = shift;
    return 0 unless LJ::is_web_context();

    my $uri = LJ::Request->uri;
    return 0 if ( $LJ::BLOCKED_BOT_URI && index( $uri, $LJ::BLOCKED_BOT_URI ) == 0 );

    # if cookie exists, check for sysban
    if (my @cookieparts = $class->parts_from_cookie) {
        my ($uniq, $uniq_time, $uniq_extra) = @cookieparts;
        return 1 if LJ::sysban_check( 'uniq', $uniq );
    }

    return 0;
}

# returns: (uniq_val, uniq_time, uniq_extra)
sub parts_from_cookie {
    my $class = shift;
    return unless LJ::is_web_context();

    my $cookieval = LJ::Request->header_in("Cookie");

    if ($cookieval =~ /\bljuniq\s*=\s*([a-zA-Z0-9]{15})(?:\:|\%3A)(\d+)([^;]+)/) {
        my ($uniq, $uniq_time, $uniq_extra) = ($1, $2, $3);
        $uniq_extra =~ s/\%3A/:/g;
        return wantarray() ? ($uniq, $uniq_time, $uniq_extra) : $uniq;
    }

    return;
}

# returns: (uniq_val, uniq_time, uniq_extra)
sub parts_from_value {
    my $class = shift;
    my $value = shift;

    if ($value =~ /^([a-zA-Z0-9]{15}):(\d+)(.+)$/) {
        return wantarray() ? ($1, $2, $3) : $1;
    }

    return;
}

sub set_current_uniq {
    my $class = shift;
    my $uniq = shift;

    $LJ::REQ_CACHE{current_uniq} = $uniq;

    return unless LJ::is_web_context();

    LJ::Request->notes('uniq' => $uniq);

    return;
}

sub current_uniq {
    my $class = shift;

    if ($LJ::_T_UNIQCOOKIE_CURRENT_UNIQ) {
        return $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ;
    }

    # should be in $LJ::REQ_CACHE, so return from
    # there if it is
    my $val = $LJ::REQ_CACHE{current_uniq};
    return $val if $val;

    # otherwise, legacy place is in $r->notes
    return unless LJ::is_web_context();

    # see if a uniq is set for this request
    # -- this accounts for cases when the cookie was initially
    #    set in this request, so it wasn't received in an 
    #    incoming headerno cookie was sent in
    $val = LJ::Request->notes('uniq');
    return $val if $val;

    $val = $class->parts_from_cookie;
    return $val;
}

1;
