package LJ::Worker::Manual;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use base 'LJ::Worker';
use LJ;

# don't override this in subclasses.
sub run {
    my $class = shift;

    LJ::Worker->setup_mother();

    my $sleep = 0;
    while (1) {
        LJ::start_request();
        LJ::Worker->check_limits();
        LJ::Worker::DEBUG("$class looking for work...");
        my $did_work = eval { $class->work };
        if ($@) {
            LJ::Worker::DEBUG("Error working: $@");
        }
        LJ::Worker::DEBUG("  did work = ", $did_work);
        exit 0 if LJ::Worker->should_quit;
        $class->on_afterwork($did_work);
        if ($did_work) {
            $sleep = 0;
            next;
        }
        $class->on_idle;

        # do some cleanup before we process another request
        LJ::end_request();

        $sleep = LJ::Worker::interval if ++$sleep > LJ::Worker::interval;
        sleep $sleep;
    }
}

sub work {
    print "NO WORK FUNCTION DEFINED\n";
    return 0;
}

sub on_afterwork { }
sub on_idle { }

1;
