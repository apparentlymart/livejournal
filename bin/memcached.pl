#!/usr/bin/perl
#
# memory cache daemon
#

use strict;
use warnings;
use lib "$ENV{'LJHOME'}/cgi-bin";
use LJ::Cache;
use Getopt::Long;
use Socket;
use POE qw(Wheel::SocketFactory
           Wheel::ReadWrite
           Driver::SysRW
           Filter::Stream);

our $debug = 0;
our $serverport = 11211;
our $MB = 2;
exit 1 unless GetOptions('port=i' => \$serverport,
                         'debug' => \$debug,
                         'MB=i' => $MB);

local $| = 1;
our $VERSION = 0.1;

fork and exit unless $debug;

my $cache = new LJ::Cache { 'maxbytes' => $MB * 1024 * 1024 };
my %stats;

POE::Session->create(
                     inline_states => {
                         _start => \&parent_start,
                         _stop  => \&parent_stop,
                         
                         socket_birth => \&socket_birth,
                         socket_death => \&socket_death,
                     }
                     );

$poe_kernel->run();
exit;

####################################

sub parent_start {
    my $heap = $_[HEAP];

    print "= L = Listener birth\n" if $debug;

    $heap->{listener} = POE::Wheel::SocketFactory->new(
        BindAddress  => '10.0.0.80',
        BindPort     => $serverport,
        Reuse        => 'yes',
        SuccessEvent => 'socket_birth',
        FailureEvent => 'socket_death',
                                                       );
}

sub parent_stop {
    my $heap = $_[HEAP];
    delete $heap->{listener};
    delete $heap->{session};
    print "= L = Listener death\n" if $debug;
}

##########
# SOCKET #
##########

sub socket_birth {
    my ( $socket, $address, $port ) = @_[ ARG0, ARG1, ARG2 ];
    $address = inet_ntoa($address);

    print "= S = Socket birth\n" if $debug;

    POE::Session->create(
                         inline_states => {
            _start => \&socket_success,
            _stop  => \&socket_death,

            socket_input => \&socket_input,
            socket_death => \&socket_death,
        },
        args => [ $socket, $address, $port ],
                         );

}

sub socket_death {
    my $heap = $_[HEAP];
    if ( $heap->{socket_wheel} ) {
        print "= S = Socket death\n" if $debug;
        delete $heap->{socket_wheel};
    }
}

sub socket_success {
    my ( $heap, $kernel, $connected_socket, $address, $port ) =
        @_[ HEAP, KERNEL, ARG0, ARG1, ARG2 ];

    print "= I = CONNECTION from $address : $port \n" if $debug;

    $heap->{state} = "waitcommand";
    $heap->{socket_wheel} = POE::Wheel::ReadWrite->new(
        Handle => $connected_socket,
        Driver => POE::Driver::SysRW->new(),
        Filter => POE::Filter::Stream->new(),

        InputEvent => 'socket_input',
        ErrorEvent => 'socket_death',
                                                       );
}

sub handle_pending_set
{
    my ($heap, $wheel) = @_;
    my $ps = $heap->{pending_set};
    if ($ps->{bytes} + 1 == $ps->{bytes_read}) {
        $stats{'cmd_set'}++;
        chop $ps->{data};
        $cache->set($ps->{key}, [ $ps->{exptime}, $ps->{data}], $ps->{bytes});
        $wheel->put("STORED\n");
    } elsif ($ps->{bytes_read} > $ps->{bytes}) {
        $wheel->put("CLIENT_ERROR too much data ($ps->{bytes_read}, not $ps->{bytes})\n");
    } else {
        $heap->{state} = "reading_set";
        return;
    }
    delete $heap->{pending_set};
    $heap->{state} = "waitcommand";
    return;
}

sub socket_input {
    my ( $heap, $buf ) = @_[ HEAP, ARG0 ];

    my $wheel = $heap->{socket_wheel};

    if ($heap->{state} eq "waitcommand") {
        if ($buf =~ /^set (\S+) (\d+) (\d+) (.*)/s) {
            my ($key, $exptime, $bytes, $data) = ($1, $2, $3, $4);
            $exptime = time() + 86400*14 unless $exptime;
            my $bytes_read = length $data;
            my $ps = $heap->{pending_set} = {
                'key' => $key,
                'exptime' => $exptime,
                'data' => $data,
                'bytes' => $bytes,
                'bytes_read' => $bytes_read,
            };
            handle_pending_set($heap, $wheel);
            return;
        }

        my @args = split(/\s+/, $buf);
        my $cmd = shift @args;
        return unless $cmd;
        if ($cmd eq "version") {
            $wheel->put("VERSION $VERSION\n");
            return;
        }
        if ($cmd eq "stats") {
            if (@args && $args[0] eq "cachedump") {
                my $now = time();
                my $shown;
                $cache->walk_items(sub {
                    return if $args[1] && ++$shown > $args[1];
                    my ($key, $bytes, $instime) = @_;
                    my $age = $now - $instime;
                    $wheel->put("ITEM $key [$bytes b; $age s]\n");
                });
            } elsif (@args && $args[0] eq "reset") {
                %stats = ();
                $wheel->put("RESET\n");
                return;
            } else {
                $wheel->put("STAT items " . $cache->get_item_count . "\n");
                $wheel->put("STAT bytes " . $cache->get_byte_count . "\n");
                my $age = $cache->get_max_age;
                $wheel->put("STAT age " . (time - $age) . "\n") if $age;
                foreach (sort keys %stats) {
                    $wheel->put("STAT $_ $stats{$_}\n");
                }
            }
            $wheel->put("END\n");
            return;
        }
        if ($cmd eq "get") {
            $stats{'cmd_get'}++;
            foreach my $key (@args) {
                my $val = $cache->get($key);
                if ($val && $val->[0] < time()) {
                    $stats{'hit_expired'}++;
                    undef $val;
                }
                if ($val) {
                    my $length = length $val->[1];
                    $wheel->put("VALUE $key $length $val->[1]\n");
                    $stats{'hit'}++;
                } else {
                    $stats{'miss'}++;
                }
            }
            $wheel->put("END\n");
            return;
        }
        $wheel->put("ERROR\n");
        return;
    } elsif ($heap->{state} eq "reading_set") {
        my $ps = $heap->{pending_set};
        my $buf_bytes = length($buf);  # includes newline, if present
        $ps->{bytes_read} += $buf_bytes;
        $ps->{data} .= $buf;
        handle_pending_set($heap,$wheel);
        return;
    }

}
