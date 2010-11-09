package LJ::NewWorker;

use strict;

use Getopt::Long;
use LJ::Worker::ErrorLog;

require 'ljlib.pl';
require 'ljprotocol.pl';
require 'ljlang.pl';

my $name        = 0;    # Name of this worker
my $quantity    = 0;    # Quantity of workers (0 means no-daemons)
my $verbose     = 0;    # Verbose output (>0 means debug mode)
my $memory_limit;       # Memory limit in bytes (undef means don't check)

my $piddir      = "/var/run/workers";
my $pidfile     = '';

my $should_quit = 0;

# Methods, which overloaded in derived classes
#sub work                    { die "Method work() was no defined in worker class" }
sub run                     { die "Method run() was no defined in worker class" }
sub options                 { return () }
sub help                    { return '' }
sub pre_fork                { }
sub after_fork              { }
sub at_exit                 { }
sub is_debug                { return 0 < $verbose }
sub work_as_script          { 0 }

sub catch_signals {
    my $self = shift;
    my $wstop = sub { $should_quit = 1; };
    $SIG{TERM}  = $wstop;
    $SIG{INT}   = $wstop;
    $SIG{CHLD}  = 'IGNORE';
    $SIG{PIPE}  = 'IGNORE';
}

sub catch_output {
    my $self = shift;
    # tie STDERR, close other standard handles
    tie(*STDERR, 'LJ::Worker::ErrorLog');
}

# $verbose get/set
sub verbose {
    my $self = shift;
    my $v = shift;
    $verbose = $v if defined($v);
    return $verbose;
}

sub should_quit {
    my $self = shift;
    my $q = shift;
    $should_quit = $q if defined($q);
    return $should_quit;
}

sub print_help {
    my $self = shift;
    print
        "Worker $self, usage options:\n" .
        "-h | --help        print this help\n" .
        "-d | --daemon n    start as daemon\n" .
        "-v | --verbose     increase verbose level\n" .
        "-m | --memory n    set memory limit to n megabytes\n",
        $self->help(),
        "\n";
        exit 0;
}

my $err = sub {
    print "ERROR $_[0]\n";
    return 0;
};

sub start {
    my $self = shift;

    die "Missed parameter in call wstart" unless $self;

    $0 =~ m|([^/]*)$|;
    $name = $1;

    # Get command line
    die "Wrong options" unless GetOptions(  'daemons|d=i'   => \$quantity,
                                            'verbose|v+'    => \$verbose,
                                            'help|h'        => sub { $self->print_help() },
                                            'memory|m=i'    => sub { $self->set_memory_limit(1024 * 1024 * $_[1]) },
                                            $self->options()
                                            );

    # Check parameters
    $quantity = abs(int($quantity)) || 0;

    # Check environment

    my $ljhome = $ENV{LJHOME} || "/home/lj";
    return $err->("\$LJHOME not defined") unless $ljhome;
    return $err->("\$LJHOME not a directory") unless -d $ljhome;

    # make sure it's set
    $ENV{LJHOME} = $ljhome;

    my $bin  = "$ljhome/bin/worker";
    return $err->("LJHOME/bin/worker directory doesn't exist") unless -d $bin;
    return $err->("bogus app name") unless $name =~ /^[\w\-]+(\.[a-z]+)?$/i;

    return if $self->work_as_script;

    my $rv = eval "use POSIX (); 1;";
    return $err->("couldn't load POSIX.pm") unless $rv;

    return $err->("piddir $piddir doesn't exist") unless -d $piddir;

    # Start
    if ($quantity) {

        # Daemonize!

        ## Change working directory
        chdir "/";

        ## Clear file creation mask
        umask 0;

        ## Fork()s processes, make sure we started and exit parent.

        my $pid;
        for(my $count = 0; $count < $quantity; ++$count) {
            $self->pre_fork(); 
            defined($pid = fork) or die "Cannot fork $!";
            if ($pid) { # Parent process.
                # Wait child started (pid file created), report 'OK' and exit.
                $pidfile = "$piddir/$name-$pid.pid";
                my $maxwait = 30;
                while (! (-r $pidfile) ) {
                    sleep 1;
                    unless ($maxwait-- > 0) {
                        print STDERR "ERROR Processes for $name worker failed to start.\n";
                        exit 0;
                    }
                }
                $self->after_fork($pid);
            } else { # Child process.
                # Detach ourselves from the terminal
                die "Cannot detach from controlling terminal"
                    unless POSIX::setsid();

                # drop root, if binary says it's okay
                my @stat = stat($0);
                if (my $uid = $stat[4]) { POSIX::setuid($uid); }
                if (my $gid = $stat[5]) { POSIX::setuid($gid); }

                # Catch all signals we needed
                $self->catch_signals();

                # Catch debug output and redirect it to webnoded or debug udp socket
                $self->catch_output();

                # Create pid-file
                $pidfile = "$piddir/$name-$$.pid";
                open(PID, '>', $pidfile) or die "Cannot create pid file: '$pidfile'";
                print PID "start time = ", time(), "\n";
                close(PID);

                # And finally go to work.
                $self->run();

                # Before exit from child, call at_exit() and remove pid file
                $self->at_exit(); unlink $pidfile;

                # And exit.
                exit 0;
            }
        }
        print STDERR "OK ALL $name workers started.\n"; # Complete loop in parent process.
    } else {
        # Catch all signals we needed
        $self->catch_signals();

        # Run at console
        $self->run();

        # Before exit, call at_exit()
        $self->at_exit();
    }

    # Exit:
    #  - from parent process to daemonize all it's childs;
    #  - if there was return from run().
    exit 0;
}

##########################
# Memory consuption checks

#use GTop ();
#my $gtop = GTop->new;
my $last_mem_check = 0;

sub set_memory_limit {
    my $class = shift;
    $memory_limit = shift;
    print STDERR "Memory limit set to ", int($memory_limit / 1024 / 1024 + 0.5), " megabytes.\n"
        if $class->verbose;
}

### May be in better future somebody implements this feature.
### Now it's a dummy method.
sub check_limits {
    my $self = shift;
    return;
#    return unless defined $memory_limit;
#    my $now = int time();
#    return if $now == $last_mem_check;
#    $last_mem_check = $now;
#
#    my $proc_mem = $gtop->proc_mem($$);
#    my $rss = $proc_mem->rss;
#    return if $rss < $memory_limit;
#
#    # Maximum ram usage greater then memory limit.
#    # Potential memory leak detected.
#    # Try to restart this worker.
#
#    die "Exceeded maximum ram usage: $rss greater than $memory_limit";
}

##
## Signal handler for debugging infinite loops
## Taken from: http://perl.apache.org/docs/1.0/guide/debug.html
## Usage: kill -USR2 <pid>
##
use Carp();
$SIG{'USR2'} = sub { Carp::confess("caught SIGUSR2!"); };

1;
