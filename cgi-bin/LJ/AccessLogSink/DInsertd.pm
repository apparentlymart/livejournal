package LJ::AccessLogSink::DInsertd;
use strict;

sub new {
    my ($class, %opts) = @_;
    return bless {}, $class;
}

sub log {
    my ($self, $rec) = @_;

    my @dinsertd_socks;
    my $now = time();

    foreach my $hostport (@LJ::DINSERTD_HOSTS) {
        next if $LJ::CACHE_DINSERTD_DEAD{$hostport} > $now - 15;

        my $sock =
            $LJ::CACHE_DINSERTD_SOCK{$hostport} ||=
            IO::Socket::INET->new(PeerAddr => $hostport,
                                  Proto    => 'tcp',
                                  Timeout  => 1,
                                  );

        if ($sock) {
            delete $LJ::CACHE_DINSERTD_DEAD{$hostport};
            push @dinsertd_socks, [ $hostport, $sock ];
        } else {
            delete $LJ::CACHE_DINSERTD_SOCK{$hostport};
            $LJ::CACHE_DINSERTD_DEAD{$hostport} = $now;
        }
    }
    return 0 unless @dinsertd_socks;

    $rec->{_table} = $rec->table;
    my $string = "INSERT " . Storable::freeze($rec) . "\r\n";
    my $len = "\x01" . substr(pack("N", length($string) - 2), 1, 3);
    $string = $len . $string;

    foreach my $rec (@dinsertd_socks) {
        my $sock = $rec->[1];
        print $sock $string;
        my $rin;
        my $res;
        vec($rin, fileno($sock), 1) = 1;
        $res = <$sock> if select($rin, undef, undef, 0.3);
        delete $LJ::CACHE_DINSERTD_SOCK{$rec->[0]} unless $res =~ /^OK\b/;
    }

}

1;
