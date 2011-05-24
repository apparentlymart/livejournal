package Apache::SendStats;
use strict;

BEGIN {
    $LJ::HAVE_AVAIL = eval "use Apache::Availability qw(count_servers); 1;";
}

use strict;
use IO::Socket::INET;
use Socket qw(SO_BROADCAST);

use vars qw(%udp_sock);

sub handler
{
    my $r = shift;
    LJ::Request->init($r) unless LJ::Request->is_inited;

    return LJ::Request::OK if LJ::Request->main;
    return LJ::Request::OK unless $LJ::HAVE_AVAIL && $LJ::FREECHILDREN_BCAST;

    my $callback = LJ::Request->is_inited ? LJ::Request->current_callback() : '';
    my $cleanup = $callback eq "PerlCleanupHandler";
    my $childinit = $callback eq "PerlChildInitHandler";

    if ($LJ::TRACK_URL_ACTIVE)
    {
        my $key = "url_active:$LJ::SERVER_NAME:$$";
        if ($cleanup) {
            LJ::MemCache::delete($key);
        } else {
            LJ::MemCache::set($key, LJ::Request->header_in("Host") . LJ::Request->uri . "(" . LJ::Request->method . "/" . scalar(LJ::Request->get_params) . ")");
          }
    }

    my ($active, $free) = count_servers();

    $free += $cleanup;
    $free += $childinit;
    $active -= $cleanup if $active;

    my $list = ref $LJ::FREECHILDREN_BCAST ?
        $LJ::FREECHILDREN_BCAST : [ $LJ::FREECHILDREN_BCAST ];

    foreach my $host (@$list) {
        next unless $host =~ /^(\S+):(\d+)$/;
        my $bcast = $1;
        my $port = $2;
        my $sock = $udp_sock{$host};
        unless ($sock) {
            $udp_sock{$host} = $sock = IO::Socket::INET->new(Proto => 'udp');
            if ($sock) {
                $sock->sockopt(SO_BROADCAST, 1)
                    if $LJ::SENDSTATS_BCAST;
            } else {
                LJ::Request->log_error("SendStats: couldn't create socket: $host");
                next;
            }
        }

        my $ipaddr = inet_aton($bcast);
        my $portaddr = sockaddr_in($port, $ipaddr);
        my $message = "bcast_ver=1\nfree=$free\nactive=$active\n";
        my $res = $sock->send($message, 0, $portaddr);
        LJ::Request->log_error("SendStats: couldn't broadcast")
            unless $res;
    }

    return LJ::Request::OK;
}

1;
