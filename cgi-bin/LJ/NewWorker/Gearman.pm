package LJ::NewWorker::Gearman;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use Gearman::Worker;
use base "LJ::NewWorker";
use LJ::WorkerResultStorage;

use LJ;
use IO::Socket::INET ();
use Carp qw(croak);

my $worker;
my $requester_id; # userid, who requested job, optional

sub gearman_set_requester_id { $requester_id = $_[0]; }

sub idle            { }

sub periodic_checks {
    my $class   = shift;
    $class->check_limits();

    # check to see if we should quit
    $worker->job_servers(@LJ::GEARMAN_SERVERS); # TODO: don't do this everytime, only when config changes?
}

sub _end_work {
    my $class   = shift;
    LJ::end_request();
    $class->periodic_checks();
};

sub run {
    my $class = shift;
    my $verbose = $class->verbose();

    print STDERR "The Gearman run().\n" if $verbose;

    ### There is a problem with DB:
    ### after long time of inactivity, DB socket is closed by DB.
    ### The first write to the socket leads to unhandled PIPE signal.
    ### This should be fixed somewhere else, actually.
    $SIG{'PIPE'} = sub { die "PIPE signal"; };

    $worker = Gearman::Worker->new();

    # Process 'declare'
    foreach my $decl ($class->declare()) {
        my ($name, $subref, $timeout) = @$decl;

        my $subrefproc = $verbose ?
            sub {
                warn "  executing '$name'...\n";
                my $ans = eval { $subref->(@_) }; # It must be call old $subref, not a recursive call.
                if ($@) {
                    warn "   -> ERR: $@\n";
                    die $@; # re-throw
                } elsif (! ref $ans && $ans !~ /^[\0\x7f-\xff]/) {
                    my $cleanans = $ans;
                    $cleanans =~ s/[^[:print:]]+//g;
                    $cleanans = substr($cleanans, 0, 1024) . "..." if length $cleanans > 1024;
                    warn "   -> answer: $cleanans\n";
                }
                return $ans;
            }
            : $subref;

        if (defined $timeout) {
            $worker->register_function($name => $timeout => $subrefproc);
        } else {
            $worker->register_function($name => $subrefproc);
        }
    }

    # Process 'work'
    my %opts = ();
    foreach my $work ($class->work()) {
        my ($key, $value) = @$work;
        $opts{$key} = $value;
    }

    my $save_result = delete $opts{save_result} || 0;

    croak "unknown opts passed to gearman_work: " . join(', ', keys %opts)
        if keys %opts;

    if ($LJ::IS_DEV_SERVER) {
        die "DEVSERVER help: No gearmand servers listed in \@LJ::GEARMAN_SERVERS.\n"
            unless @LJ::GEARMAN_SERVERS;
        IO::Socket::INET->new(PeerAddr => $LJ::GEARMAN_SERVERS[0])
            or die "First gearmand server in \@LJ::GEARMAN_SERVERS ($LJ::GEARMAN_SERVERS[0]) isn't responding.\n";
    }

    # save the results of this worker
    my $storage;

    my $last_death_check = time();

    while ( ! $class->should_quit() ) {
        $class->periodic_checks();
        print STDERR "Gearman waiting for work...\n" if $verbose;

        # do the actual work
        eval {
            $worker->work(
                on_start    => sub {
                    my $handle = shift;

                    LJ::start_request();
                    undef $requester_id;

                    # save to db that we are starting the job
                    if ($save_result) {
                        $storage = LJ::WorkerResultStorage->new(handle => $handle);
                        $storage->init_job;
                    }
                },
                stop_if     => sub { $_[0] },
                on_complete => sub {    # callback to save job status
                    $class->_end_work();
                    my ($handle, $res) = @_;
                    $res ||= '';

                    if ($save_result && $storage) {
                        my %row = (result   => $res,
                                   status   => 'success',
                                   end_time => 1);
                        $row{userid} = $requester_id if defined $requester_id;
                        $storage->save_status(%row);
                    }
                },
                on_fail     => sub {
                    $class->_end_work();
                    my ($handle, $err) = @_;
                    $err ||= '';

                    if ($save_result && $storage) {
                        my %row = (result   => $err,
                                   status   => 'error',
                                   end_time => 1);
                        $row{userid} = $requester_id if defined $requester_id;
                        $storage->save_status(%row);
                    }
                },
            );
        };
        warn $@ if $@;

        print STDERR "Gearman idle...\n" if $verbose;
        eval { 
            LJ::start_request();
            $class->idle();
            LJ::end_request();
        };
        warn $@ if $@;
    }
}

1;
