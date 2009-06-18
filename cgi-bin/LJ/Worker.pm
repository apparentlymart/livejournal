package LJ::Worker;

use strict;

use IO::Socket::UNIX ();
use POSIX ();

use Getopt::Long qw(:config pass_through); # We get only -v option, and leave all other for future using.

# this will force preloading (rather than lazy) or all
# modules so they're loaded in shared memory before the
# fork (mod_perl-style)
use Class::Autouse qw{:devel};

use LJ::Worker::ErrorLog;

my $quit_flag = 0;
my $interval  = 5;

BEGIN {
    $SIG{TERM} = sub { $quit_flag = 1; };

    # This variable increased if option -v|--verbose specified
    # or in DEBUG environment variable if it is not empty.
    my $verbose = 0;
    die "Wrong options" unless GetOptions('verbose|v+' => \$verbose,
                                          'interval|i' => \$interval);
    $verbose = int($ENV{DEBUG}) if $ENV{DEBUG};

    # Access to this var by VERBOSE sub
    eval "sub VERBOSE () { $verbose }";
    eval "sub DEBUG {
            return \$verbose unless \$verbose && scalar \@_;
            my \$l = join('', map { \$_ || '' } \@_);
            \$l .= \"\n\" if \$l && \$l !~ m/\\n\$/;
            print STDERR \$l;
            return \$verbose;
          }";
}

sub interval { $interval }

my $original_name = $0;
my $mother_sock_path;

sub socket_filename {
    return "/var/run/workers/$_[1].sock";
}

sub _pid_file_path {
    $original_name =~ m{([^/]+)$};
    my $name = $1;
    return "/var/run/gearman/$name.$$";
}

sub should_quit {
    unlink _pid_file_path if $quit_flag;
    return $quit_flag;
}

##############################
# Child and forking management

my $fork_count = 0;

sub setup_mother {
    my $class = shift;

    return unless $ENV{SETUP_MOTHER};

    # tie STDERR for mother process
    tie(*STDERR, 'LJ::Worker::ErrorLog');

    # Curerntly workers use a SIGTERM handler to prevent shutdowns in the middle of operations,
    # we need TERM to apply right now in this code
    local $SIG{TERM};
    local $SIG{CHLD} = "IGNORE";
    local $SIG{PIPE} = "IGNORE";

    my ($function) = $0 =~ m{([^/]+)$};
    my $sock_path = $class->socket_filename($function);

    DEBUG("Checking for existing mother at $sock_path");

    if (my $sock = IO::Socket::UNIX->new(Peer => $sock_path)) {
        DEBUG("Asking other mother to stand down. We're in charge now");
        print $sock "SHUTDOWN\n";
    }

    unlink $sock_path; # No error trap, the file may not exist
    my $listener = IO::Socket::UNIX->new(Local => $sock_path, Listen => 1);

    die "Error creating listening unix socket at '$sock_path': $!" unless $listener;

    DEBUG("Waiting for input");
    local $0 = "$original_name [mother]";
    $mother_sock_path = $sock_path;
    while (accept(my $sock, $listener)) {
        $sock->autoflush(1);
        while (my $input = <$sock>) {
            chomp $input;

            my $method = "MANAGE_" . lc($input);
            if (my $cv = $class->can($method)) {
                DEBUG("Executing '$method' function");
                my $rv = $cv->($class);
                return unless $rv; #return value of command handlers determines if the loop stays running.
                print $sock "OK $rv\n";
            } else {
                print $sock "ERROR unknown command\n";
            }
        }
    }
}

sub MANAGE_shutdown {
    my $class = shift;
    exit;
}

sub MANAGE_fork {
    my $class = shift;

    my $pid = fork();

    unless (defined $pid) {
        warn "Couldn't fork: $!";
        return 1; # continue running the management loop if we can't fork
    }

    if ($pid) {
        $fork_count++;
        $0 = "$original_name [mother] $fork_count";
        # Return the pid, true value to continue the loop, pid for webnoded to track children.
        return $pid;
    }

    # Create pid file
    my $pidfilename = _pid_file_path;
    my $pidfile;
    open($pidfile, '>', $pidfilename) or die "can't write to pidfile $pidfilename: $!";
    my $now = time();
    my $ltime = localtime($now);
    print $pidfile "start: $now ($ltime)\n";
    close $pidfile;

    POSIX::setsid();
    $SIG{HUP} = 'IGNORE';

    # tie STDERR for worker process
    tie(*STDERR, 'LJ::Worker::ErrorLog');

    return 0; # we're a child process, the management loop should cleanup and end because we want to start up the main worker loop.
}

##########################
# Memory consuption checks

use GTop ();
my $gtop = GTop->new;
my $last_mem_check = 0;

my $memory_limit;

sub set_memory_limit {
    my $class = shift;
    $memory_limit = shift;
}

sub check_limits {
    return unless defined $memory_limit;
    my $now = int time();
    return if $now == $last_mem_check;
    $last_mem_check = $now;

    my $proc_mem = $gtop->proc_mem($$);
    my $rss = $proc_mem->rss;
    return if $rss < $memory_limit;

    if ($mother_sock_path and my $sock = IO::Socket::UNIX->new(Peer => $mother_sock_path)) {
        print $sock "FORK\n";
        close $sock;
    } else {
        warn "Unable to contact mother process at $mother_sock_path";
    }
    die "Exceeded maximum ram usage: $rss greater than $memory_limit";
}

1;
