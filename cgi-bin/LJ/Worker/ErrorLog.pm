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
    my $dest_point = shift || "$LJ::WATCHLOG_BCASTADDR:$LJ::WATCHLOG_PORTNO";

    my $dest_proto = 'udp';

    my @dest = split(/:/, $dest_point);

    if (3 == scalar @dest) {
        $dest_proto = $dest[0];
        $dest_point = join(':', $dest[1], $dest[2]);
    }

    my $sock = IO::Socket::INET->new(PeerAddr => $dest_point, Proto => $dest_proto, Broadcast => 1, Timeout => 20)
        or die "Socket error: $!";

    my $self = { handles => { sock => $sock } };

    bless $self, $class;

    $self->reopen_handles;

    return $self;
}

sub reopen_handles {
    my $self = shift;
    my $force = shift;

    # In debug mode, when worker started from console,
    # we must not close STDERR to let to see error messages on a console.

    if ($force or (-t STDIN) or (-t STDOUT) or (-t STDERR)) {
        # Save old, was not tied yet STDERR handle to use it for printing later.
        open(OLDSTDERR, "+>&STDERR");
        $self->{handles}->{stderr} = \*OLDSTDERR;
        print OLDSTDERR "$0: Debug mode: control console is a terminal, don't detach from it.\n";
    } else {
        ## Reopen stderr, stdout, stdin to /dev/null
        close(STDIN);   open(STDIN,  "+>/dev/null");
        close(STDOUT);  open(STDOUT, "+>/dev/null");
        close(STDERR);  open(STDERR, "+>/dev/null");
    }
}

# warn, die and print STDERR

sub PRINT {
    my $self = shift;
    my $str = join($,,@_); chomp ($str);
    my $now = time();
    my $ltime = localtime($now);
    foreach my $k ( keys %{$self->{handles}} ) {
        print { $self->{handles}->{$k} } 'ap_wrk:', $ltime, ': ', $str, ('stderr' eq $k ? "\n" : "");
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
