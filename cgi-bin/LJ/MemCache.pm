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
    $key = ref $key eq "ARRAY" ? $key->[0] : $key;
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

sub delete {
    my $key = shift;
    set($key, "", 1);  # no value, and expires at the beginning of time
    # FIXME: ideally this should send the cache server a real "delete" command
    # so the server can ignore sets for 'n' seconds thereafter, to mitigate
    # race conditions
}

sub set {
    return 0 unless @LJ::MEMCACHE_SERVERS;
    my ($key, $val, $exptime) = @_;
    my $sock = get_sock($key);
    return 0 unless $sock;
    my $flags;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
    if (ref $val) {
        $val = Storable::freeze($val);
        $flags .= "S";
    }
    my $len = length($val);
    $exptime = int($exptime)+0;
    $flags ||= "-";
    my $cmd = "set $key $flags $exptime $len $val\n";
    $sock->print($cmd);
    $sock->flush;
    my $line = <$sock>;
    return 1 if $line eq "STORED\n";
}

sub get {
    my ($key) = @_;
    my $val = get_multi($key);
    return undef unless $val;
    return $val->{$key};
}

sub get_multi {
    return undef unless @LJ::MEMCACHE_SERVERS;
    my %val;        # what we'll be returning a reference to (realkey -> value)
    my %sock_keys;  # sockref_as_scalar -> [ realkeys ]
    my @socks;      # unique socket refs
    foreach my $key (@_) {
        my $sock = get_sock($key);
        next unless $sock;
        $key = ref $key eq "ARRAY" ? $key->[1] : $key;
        unless ($sock_keys{$sock}) {
            $sock_keys{$sock} = [];
            push @socks, $sock;
        }
        push @{$sock_keys{$sock}}, $key;
    }
    foreach my $sock (@socks) {
        _load_items($sock, \%val, @{$sock_keys{$sock}});
    }
    return \%val;
}

sub _load_items
{
    my $sock = shift;
    my $outref = shift;

    my %flags;
    my %val;

    my $cmd = "get @_\n";
    $sock->print($cmd);
    $sock->flush;
  ITEM:
    while (1) {
        my $line = $sock->getline;
        if ($line =~ /^VALUE (\S+) (\S+) (\d+) (.*)/s) {
            my ($rk, $flags, $len, $data) = ($1, $2, $3, $4);
            my $this_len = length($data);
            $flags{$rk} = $flags unless $flags eq "-";
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
                    return 0;
                }
            }
            next ITEM;
        }
        if ($line eq "END\n") {
            foreach (@_) {
                next unless $val{$_};
                $val{$_} = Storable::thaw($val{$_}) if $flags{$_} =~ /S/;
                $outref->{$_} = $val{$_};
            }
            return 1;
        }
        if (length($line) == 0) {
            return 0;
        }
    }
}

1;
