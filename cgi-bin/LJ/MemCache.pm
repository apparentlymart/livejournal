#!/usr/bin/perl
#

use strict;
use IO::Socket::INET;

package LJ::MemCache;

sub get_sock
{
    my ($hasher, $key) = @_;
    return undef unless @LJ::MEMCACHE_SERVERS;
    my $host = $LJ::MEMCACHE_SERVERS[0];

    return $LJ::MemCache::CACHE_SOCK{$host} if $LJ::MemCache::CACHE_SOCK{$host};

    my $sock = IO::Socket::INET->new(Proto => "tcp",
                                     PeerAddr => $host,
                                     Timeout => 2);
    return undef unless $sock;

    return $LJ::MemCache::CACHE_SOCK{$host} = $sock;
}

sub disconnect_all
{
    $_->close foreach (values %LJ::MemCache::CACHE_SOCK);
    %LJ::MemCache::CACHE_SOCK = ();
}

sub set {
    my ($hasher, $key, $val) = @_;
    my $sock = get_sock($hasher, $key);
    return 0 unless $sock;
    my $len = length($val);
    my $cmd = "set $key 0 $len $val\n";
    $sock->print($cmd);
    $sock->flush;
    my $line = <$sock>;
    return 1 if $line eq "STORED\n";
}

sub get {
    my ($hasher, $key) = @_;
    my $sock = get_sock($hasher, $key);
    return undef unless $sock;
    my $cmd = "get $key\n";
    $sock->print($cmd);
    $sock->flush;
    my %val;
  ITEM:
    while (1) {
        my $line = $sock->getline;
        if ($line =~ /^VALUE (\S+) (\d+) (.*)/s) {
            my ($rk, $len, $data) = ($1, $2, $3);
            my $this_len = length($data);
            if ($this_len == $len + 1) {
                chop $data;
                $val{$rk} = $data;
                next ITEM;
            }
            my $bytes_read = $this_len;
            my $buf = $data;
            while ($line = $sock->getline, $line ne "") {
                $bytes_read += length($line);
                $buf .= $line;
                if ($bytes_read == $len + 1) {
                    chop $buf;
                    $val{$rk} = $buf;
                    next ITEM;
                }
                if ($bytes_read > $len) {
                    # invalid crap from server
                    return undef;
                }
            }
            next ITEM;
        }
        if ($line eq "END\n") {
            return $val{$key};
        }
        if (length($line) == 0) {
            return undef;
        }
    }
}

1;
