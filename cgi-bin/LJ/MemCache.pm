#!/usr/bin/perl
#

use strict;
use IO::Socket::INET;
use Storable ();

package LJ::MemCache;

my %host_dead;   # host -> unixtime marked dead until
my %cache_sock;  # host -> socket

my $buckets;
my @buckets;

sub hashfunc
{
    my $hash = 0;
    foreach (split //, shift) {
        $hash = $hash*33 + ord($_);
    }
    return $hash;
}

sub trigger_bucket_reconstruct {
    @buckets = ();
    $buckets = 0;
}

sub sock_to_host # (host)
{
    my $host = shift;
    my $now = time();
    return undef if $host_dead{$host} > $now;
    return $cache_sock{$host} if $cache_sock{$host} && $cache_sock{$host}->connected;
    my $sock = IO::Socket::INET->new(Proto => "tcp",
                                     PeerAddr => $host,
                                     Timeout => 2);
    unless ($sock) {
        $host_dead{$host} = $now + 10 + int(rand(10));
        return undef;
    }
    return $cache_sock{$host} = $sock;
}

sub get_sock # (key)
{
    return undef unless @LJ::MEMCACHE_SERVERS;
    my $key = shift;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
    my $hv = hashfunc($key);

    unless (@buckets) {
        foreach my $v (@LJ::MEMCACHE_SERVERS) {
            if (ref $v eq "ARRAY") {
                for (1..$v->[1]) { push @buckets, $v->[0]; }
            } else { 
                push @buckets, $v; 
            }
        }
        $buckets = @buckets;
    }

    my $tries = 0;
    while ($tries++ < 20) {
        my $host = $buckets[$hv % $buckets];
        my $sock = sock_to_host($host);
        return $sock if $sock;
        $hv += hashfunc($tries);  # stupid, but works
    }
    return undef;
}

sub disconnect_all
{
    $_->close foreach (values %cache_sock);
    %cache_sock = ();
}

sub set {
    my ($key, $val) = @_;
    my $sock = get_sock($key);
    return 0 unless $sock;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
    my $len = length($val);
    my $cmd = "set $key 0 $len $val\n";
    $sock->print($cmd);
    $sock->flush;
    my $line = <$sock>;
    return 1 if $line eq "STORED\n";
}

sub get {
    my ($key) = @_;
    my $sock = get_sock($key);
    return undef unless $sock;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
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
