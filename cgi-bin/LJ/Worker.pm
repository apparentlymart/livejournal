package LJ::Worker;

use IO::Socket::UNIX;
use Socket;

BEGIN {
    my $debug = $ENV{DEBUG} ? 1 : 0;
    eval "sub DEBUG () { $debug }";
}

##############################
# Child and forking management

sub setup_mother {
    my $class = shift;

    return unless $ENV{SETUP_MOTHER};
    my ($function) = $0 =~ m{([^/]+)$};
    my $sock_path = "/var/run/workers/$function.sock";

    warn "Checking for existing mother at $sock_path" if DEBUG;

    if (my $sock = IO::Socket::UNIX->new(Peer => $sock_path, Type => SOCK_DGRAM)) {
        warn "Asking other mother to stand down. We're in charge now" if DEBUG;
        print $sock "SHUTDOWN\n";
    } else {
        warn "Other mother didn't exist: $!";
    }

    unlink $sock_path; # No error trap, the file may not exist
    my $sock = IO::Socket::UNIX->new(Local => $sock_path, Listen => 1, Type => SOCK_DGRAM);

    die "Error creating listening unix socket at '$sock_path': $!" unless $sock;

    warn "Waiting for input" if DEBUG;
    while (my $input = <$sock>) {
        chomp $input;

        my $method = "MANAGE_" . uc($input);
        if (my $cv = $class->can($method)) {
            warn "Executing '$method' function" if DEBUG;
            my $rv = $cv->($class);
            return unless $rv; #return value of command handlers determines if the loop stays running.
        }
    }
}

sub MANAGE_SHUTDOWN {
    exit;
}

sub MANAGE_FORK {
    my $pid = fork();

    unless (defined $pid) {
        warn "Couldn't fork: $!";
        return 1; # continue running the management loop if we can't fork
    }

    if ($pid) {
        return 1; # continue the management loop because we're the parent
    } else {
        return 0; # we're a child process, the management loop should cleanup and end because we want to start up the main worker loop.
    }

    return $pid;
}

1;
