package LJ::NewWorker::Manual;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use base 'LJ::NewWorker';
use LJ;

my  $interval   = 10;

sub options {
    my $self = shift;
    return (
        'interval|i=i'  => \$interval,
        $self->SUPER::options(),
    );
}

sub help {
    my $self = shift;
    return
        $self->SUPER::help() .
        "-i | --interval n  set sleep interval to n secounds\n";
}

# don't override this in subclasses.
sub run {
    my $class = shift;

    my $verbose = $class->verbose;

    $interval = 10 unless $interval;

    my $sleep = 0;
    while (1) {
        LJ::start_request();
        $class->check_limits();
        print STDERR "$class looking for work...\n" if $verbose;
        my $did_work = eval { $class->work };
        if ($@) {
            print STDERR "Error working: $@";
        }
        print STDERR "  did work = ", ($did_work || ''), "\n" if $verbose;
        return if $class->should_quit;
        $class->on_afterwork($did_work);
        if ($did_work) {
            $sleep = 0;
            next;
        }
        $class->on_idle;

        # do some cleanup before we process another request
        LJ::end_request();

        $sleep = $interval if ++$sleep > $interval;
        sleep $sleep;

        return if $class->should_quit;
    }
}

sub work {
    print STDERR "NO WORK FUNCTION DEFINED\n";
    return 0;
}

sub on_afterwork { }
sub on_idle { }

1;
