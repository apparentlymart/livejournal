package LJ::NewWorker;

use strict;

use Getopt::Long;
use LJ::Worker::ErrorLog;
use POSIX;

require 'ljlib.pl';
require 'ljprotocol.pl';
use LJ::Lang;

my $name        = 0;    # Name of this worker
my $quantity    = 0;    # Quantity of workers (0 means no-daemons)
my $verbose     = 0;    # Verbose output (>0 means debug mode)
my $memory_limit;       # Memory limit in bytes (undef means don't check)

my $piddir      = "/var/run/workers";
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
    die "\$LJHOME not a directory" unless -d $ljhome;

    # make sure it's set
    $ENV{LJHOME} = $ljhome;

    my $bin  = "$ljhome/bin/worker";
    die "LJHOME/bin/worker directory doesn't exist" unless -d $bin;
    die "piddir $piddir doesn't exist" unless -d $piddir;

    # Start
    if ($quantity) {

        # Daemonize!

        ## Change working directory
        chdir "/";

        ## Clear file creation mask
        umask 0;

        ## Fork()s processes, make sure we started and exit parent.
        
        $self->pre_fork(); 

        my $pid;
        my %children_pids;      ## list of child processes for parent
        for (my $count = 0; $count < $quantity; ++$count) {
            defined($pid = fork) or die "Cannot fork $!";
            if ($pid) { 
                # Parent process.
                $children_pids{$pid}++;
            } else { 
                # Child process.
                $self->after_fork();

                # Detach ourselves from the terminal
                die "Cannot detach from controlling terminal"
                    unless POSIX::setsid();

                # drop root, if binary says it's okay
                my @stat = stat($0);
                if (my $uid = $stat[4]) { POSIX::setuid($uid); }
                if (my $gid = $stat[5]) { POSIX::setuid($gid); }

                # Catch all signals we needed
                $self->catch_signals();

                # Create pid-file
                my $pidfile = "$piddir/$name-$$.pid";
                open(PID, '>', $pidfile) or die "Cannot create pid file: '$pidfile'";
                print PID "start time = ", time(), "\n";
                close(PID);

                # Catch debug output and redirect it to debug udp socket
                $self->catch_output();

                # And finally go to work.
                $self->run();

                # Before exit from child, call at_exit() and remove pid file
                $self->at_exit(); 
                unlink $pidfile;

                # And exit.
                exit 0;
            }
        }

        ## parent
        ## Wait for children to start (pid file created) and exit.
        my $maxwait = 30;
        while (1) {
            foreach my $pid (keys %children_pids) {
                my $pidfile = "$piddir/$name-$pid.pid";
                if (-r $pidfile) {
                    delete $children_pids{$pid};
                }
            }

            my @pids = keys %children_pids;
            my $count = scalar @pids;

            unless ($count) {
                ## all childs started and created pid files
                print STDERR "# $quantity worker(s) $name started\n"; # Complete loop in parent process.
                exit 0;
            }

            if ($maxwait-- <= 0) {
                print STDERR "# $count of $quantity worker(s) $name failed to start (@pids)\n";
                exit 1;
            }
            
            if (($maxwait%10) == 1) {
                print STDERR "# waiting for $count worker(s) $name to start\n";
            }

            sleep 1;
        }
    } else {
        # Catch all signals we needed
        $self->catch_signals();
        $self->pre_fork(); 
        $self->after_fork();

        # Run at console
        $self->run();

        # Before exit, call at_exit()
        $self->at_exit();
    }
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
