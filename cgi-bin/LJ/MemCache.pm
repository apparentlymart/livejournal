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

sub forget_dead_hosts
{
    %host_dead = ();
}

sub sock_to_host # (host)
{
    my $host = shift;
    my $now = time();
    my ($ip, $port) = $host =~ /(.*):(.*)/;
    return undef if 
         $host_dead{$host} && $host_dead{$host} > $now || 
         $host_dead{$ip} && $host_dead{$ip} > $now;
    return $cache_sock{$host} if $cache_sock{$host} && $cache_sock{$host}->connected;
    my $sock = IO::Socket::INET->new(Proto => "tcp",
                                     PeerAddr => $host,
                                     Timeout => 1);
    unless ($sock) {
        $host_dead{$host} = $host_dead{$ip} = $now + 60 + int(rand(10));
        return undef;
    }
    return $cache_sock{$host} = $sock;
}

sub get_sock # (key)
{
    return undef unless @LJ::MEMCACHE_SERVERS;
    my $key = shift;
    my $hv = ref $key eq "ARRAY" ? int($key->[0]) : hashfunc($key);

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
    return 0 unless @LJ::MEMCACHE_SERVERS;
    my $key = shift;
    my $sock = get_sock($key);
    return 0 unless $sock;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
    my $cmd = "delete $key\r\n";
    $sock->print($cmd);
    $sock->flush;
    my $line = <$sock>;
    return 1 if $line eq "DELETED\r\n";
}

sub add {
    _set("add", @_);
}

sub replace {
    _set("replace", @_);
}

sub set {
    _set("set", @_);
}

sub _set {
    return 0 unless @LJ::MEMCACHE_SERVERS;
    my ($cmdname, $key, $val, $exptime) = @_;
    my $sock = get_sock($key);
    return 0 unless $sock;
    my $flags = 0;
    $key = ref $key eq "ARRAY" ? $key->[1] : $key;
    my $raw_val = $val;
    if (ref $val) {
        $val = Storable::freeze($val);
        $flags |= 1;
    }
    my $len = length($val);
    $exptime = int($exptime || 0);
    my $cmd = "$cmdname $key $flags $exptime $len\r\n$val\r\n";
    $sock->print($cmd);
    $sock->flush;
    my $line = <$sock>;
    if ($line eq "STORED\r\n") {
        print STDERR "MemCache: $cmdname $key = $raw_val\n" if $LJ::MEMCACHE_DEBUG;
        return 1;
    }
    return 0;
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
    if ($LJ::MEMCACHE_DEBUG) {
        while (my ($k, $v) = each %val) {
            print STDERR "MemCache: got $k = $v\n";
        }
    }
    return \%val;
}

sub _load_items
{
    my $sock = shift;
    my $outref = shift;

    my %flags;
    my %val;
    my %len;   # key -> intended length

    my $cmd = "get @_\r\n";
    $sock->print($cmd);
    $sock->flush;
  ITEM:
    while (1) {
        my $line = $sock->getline;
        if ($line =~ /^VALUE (\S+) (\d+) (\d+)\r\n$/s) {
            my ($rk, $flags, $len) = ($1, $2, $3);
            $flags{$rk} = $flags if $flags;
            $len{$rk} = $len;
            my $bytes_read = 0;
            my $buf;
            while (defined($line = $sock->getline)) {
                $bytes_read += length($line);
                $buf .= $line;
                if ($bytes_read == $len + 2) {
                    chop $buf; chop $buf;  # kill \r\n
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
        if ($line eq "END\r\n") {
            foreach (@_) {
                next unless length($val{$_}) == $len{$_};
                $val{$_} = Storable::thaw($val{$_}) if $flags{$_} & 1;
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
