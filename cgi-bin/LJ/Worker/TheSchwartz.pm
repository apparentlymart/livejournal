package LJ::Worker::TheSchwartz;
use strict;
use lib "$ENV{LJHOME}/cgi-bin";

require "ljlib.pl";
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Getopt::Long;

my $interval = 5;
my $verbose  = 0;
die "Unknown options" unless
    GetOptions('interval|n=i' => \$interval,
               'verbose|v'    => \$verbose);

my $quit_flag = 0;
$SIG{TERM} = sub {
    $quit_flag = 1;
};

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(schwartz_decl schwartz_work schwartz_on_idle schwartz_on_afterwork schwartz_on_prework);

my $sclient = LJ::theschwartz();
$sclient->set_verbose($verbose);

my $on_idle = sub {};
my $on_afterwork = sub {};

my $on_prework = sub { 1 };  # return 1 to proceed and do work

sub schwartz_decl {
    my ($classname) = @_;
    $sclient->can_do($classname);
}

sub schwartz_on_idle {
    my ($code) = @_;
    $on_idle = $code;
}

sub schwartz_on_afterwork {
    my ($code) = @_;
    $on_afterwork = $code;
}

# coderef to return 1 to proceed, 0 to sleep
sub schwartz_on_prework {
    my ($code) = @_;
    $on_prework = $code;
}

sub schwartz_work {
    my $sleep = 0;
    while (1) {
        LJ::start_request();
        my $did_work = 0;
        if ($on_prework->()) {
            $did_work = $sclient->work_once;
            $on_afterwork->($did_work);
            exit 0 if $quit_flag;
        }
        if ($did_work) {
            $sleep = 0;
            next;
        }
        $on_idle->();
        $sleep = $interval if ++$sleep > $interval;
        sleep $sleep;
    }
}

1;
