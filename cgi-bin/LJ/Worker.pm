package LJ::Worker;

use IO::Socket::UNIX;
use POSIX ":sys_wait_h";

my %child_pids;
    # Key is PID, value is time when the prcess was forked (technically a tiny bit after)

sub setup_mother {
    my $class = shift;

    return unless $ENV{SETUP_MOTHER};
    my $sock_path = "/var/lib/run/$0.sock";

    if (my $sock = IO::Socket::UNIX->new(Peer => $sock_path)) {
        print $sock "SHUTDOWN\n";
    }

    unlink $sock_path; # No error trap, the file may not exist
    my $sock = IO::Socket::UNIX->new(Local => $sock_path, Listen => 1);

    die "Error creating listening unix socket at '$sock_path': $!" unless $sock;

    local $SIG{CHLD} = \&reap_children;

    while (my $input = <$sock>) {
        chomp $input;

        my $method = "MANAGE_" . uc($input);
        if (my $cv = $class->can($method)) {
            my $rv = $cv->($class);
            return unless $rv; #return value of command handlers determines if the loop stays running.
        }
    }
}

sub reap_children {
    local $!;
    local $?;

    while (my $pid = waitpid(-1, WNOHANG)) {
        return unless $pid > 0;

        my $startup_time = $child_pids{$pid};
        return unless $startup_time; # Not my child?
    }
}

sub MANAGE_SHUTDOWN {
    exit;
}

sub MANAGE_FORK {
    local $SIG{CHLD} = "DEFAULT"; # Don't race
    my $pid = fork();

    unless (defined $pid) {
        warn "Couldn't fork: $!";
        return 1; # continue running the management loop if we can't fork
    }

    if ($pid) {
        $child_pids{$pid} = time; # Shove the time in, because we don't have anything better to track at the moment.
        reap_children();
        $0 = "$0 [C:" . scalar(keys %child_pids) . "]";
        return 1; # continue the management loop because we're the parent
    } else {
        return 0; # we're a child process, the management loop should cleanup and end because we want to start up the main worker loop.
    }

    return $pid;
}
