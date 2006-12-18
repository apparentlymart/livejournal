#
# Wrapper around MemCachedClient

use lib "$ENV{'LJHOME'}/cgi-bin";
use Cache::Memcached;
use strict;

package LJ::MemCache;

use vars qw($GET_DISABLED);
$GET_DISABLED = 0;

%LJ::MEMCACHE_ARRAYFMT = (
                          'user' =>
                          [qw[1 userid user caps clusterid dversion email password status statusvis statusvisdate
                              name bdate themeid moodthemeid opt_forcemoodtheme allow_infoshow allow_contactshow
                              allow_getljnews opt_showtalklinks opt_whocanreply opt_gettalkemail opt_htmlemail
                              opt_mangleemail useoverrides defaultpicid has_bio txtmsg_status is_system
                              journaltype lang oldenc]],
                          'fgrp' => [qw[1 userid groupnum groupname sortorder is_public]],
                          # version #101 because old userpic format in memcached was an arrayref of
                          # [width, height, ...] and widths could have been 1 before, although unlikely
                          'userpic' => [qw[101 width height userid fmt state picdate location flags]],
                          'talk2row' => [qw[1 nodetype nodeid parenttalkid posterid datepost state]],
                          );


my $memc;  # memcache object

sub init {
    $memc = new Cache::Memcached;
    reload_conf();
}

sub set_memcache {
    $memc = shift;
}

sub get_memcache {
    init() unless $memc;
    return $memc
}

sub client_stats {
    return $memc->{'stats'} || {};
}

sub reload_conf {
    my $stat_callback;
    return $memc if eval { $memc->doesnt_want_configuration; };

    $memc->set_servers(\@LJ::MEMCACHE_SERVERS);
    $memc->set_debug($LJ::DEBUG{'memcached'});
    $memc->set_pref_ip(\%LJ::MEMCACHE_PREF_IP);
    $memc->set_compress_threshold($LJ::MEMCACHE_COMPRESS_THRESHOLD);

    $memc->set_connect_timeout($LJ::MEMCACHE_CONNECT_TIMEOUT);
    $memc->set_cb_connect_fail($LJ::MEMCACHE_CB_CONNECT_FAIL);

    if ($LJ::DB_LOG_HOST) {
        $stat_callback = sub {
            my ($stime, $etime, $host, $action) = @_;
            LJ::blocking_report($host, 'memcache', $etime - $stime, "memcache: $action");
        };
    } else {
        $stat_callback = undef;
    }
    $memc->set_stat_callback($stat_callback);
    $memc->set_readonly(1) if $ENV{LJ_MEMC_READONLY};
    return $memc;
}

sub forget_dead_hosts { $memc->forget_dead_hosts(); }
sub disconnect_all    { $memc->disconnect_all();    }

sub delete {
    # use delete time if specified
    return $memc->delete(@_) if defined $_[1];

    # else default to 4 seconds:
    # version 1.1.7 vs. 1.1.6
    $memc->delete(@_, 4) || $memc->delete(@_);
}

sub add       { $memc->add(@_);       }
sub replace   { $memc->replace(@_);   }
sub set       { $memc->set(@_);       }
sub incr      { $memc->incr(@_);      }
sub decr      { $memc->decr(@_);      }

sub get       {
    return undef if $GET_DISABLED;
    $memc->get(@_);
}
sub get_multi {
    return {} if $GET_DISABLED;
    $memc->get_multi(@_);
}

sub _get_sock { $memc->get_sock(@_);   }

sub run_command { $memc->run_command(@_); }


sub array_to_hash {
    my ($fmtname, $ar) = @_;
    my $fmt = $LJ::MEMCACHE_ARRAYFMT{$fmtname};
    return undef unless $fmt;
    return undef unless $ar && ref $ar eq "ARRAY" && $ar->[0] == $fmt->[0];
    my $hash = {};
    my $ct = scalar(@$fmt);
    for (my $i=1; $i<$ct; $i++) {
        $hash->{$fmt->[$i]} = $ar->[$i];
    }
    return $hash;
}

sub hash_to_array {
    my ($fmtname, $hash) = @_;
    my $fmt = $LJ::MEMCACHE_ARRAYFMT{$fmtname};
    return undef unless $fmt;
    return undef unless $hash && ref $hash;
    my $ar = [$fmt->[0]];
    my $ct = scalar(@$fmt);
    for (my $i=1; $i<$ct; $i++) {
        $ar->[$i] = $hash->{$fmt->[$i]};
    }
    return $ar;
}

sub get_or_set {
    my ($memkey, $code) = @_;
    my $val = LJ::MemCache::get($memkey);
    return $val if $val;
    $val = $code->();
    LJ::MemCache::set($memkey, $val);
    return $val;
}

1;
