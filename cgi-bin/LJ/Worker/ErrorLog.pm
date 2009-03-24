package LJ::Worker::ErrorLog;

use strict;

use IO::Socket::INET;

# Use this like:
# use LJ::Worker::ErrorLog;
#  tie(*STDERR, 'LJ::Worker::ErrorLog', 'udp:localhost:6101');
#  warn 'Test Error Log';

# Constructor

sub TIEHANDLE {
    my $class = shift;
    my $dest_point = shift or "$LJ::WATCHLOG_MYNET:$LJ::WATCHLOG_PORTNO";

    my $dest_proto = 'udp';

    my @dest = split(/:/, $dest_point);

    if (3 == scalar @dest) {
        $dest_proto = @dest[0];
        $dest_point = join(':', $dest[1], $dest[2]);
    }

    my $sock = IO::Socket::INET->new(PeerAddr => $dest_point, Proto => $dest_proto, Timeout => 20)
        or die "Socket error: $!";

    my $self = { sock => $sock, };

    return bless $self, $class
}

# warn, die and print STDERR

sub PRINT {
    my $self = shift;
    if ($self->{sock}) {
        my $now = time();
        my $ltime = localtime($now);
        print { $self->{sock} } $ltime, ': ', join($,,@_),$\;
    }
}

# handle operations

sub OPEN {
#    my $self = shift;
#    $self->PRINT("Open called.\n");
}

sub CLOSE {
#    my $self = shift;
#    $self->PRINT("Close called.\n");
}

sub UNTIE {
#    my $self = shift;
#    $self->PRINT("Untie called.\n");
}

1;
