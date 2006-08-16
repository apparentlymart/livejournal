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
@EXPORT = qw(schwartz_decl schwartz_work);

my $sclient = LJ::theschwartz();
$sclient->set_verbose($verbose);

sub schwartz_decl {
    my ($classname) = @_;
    $sclient->can_do($classname);
}

sub schwartz_work {
    my $sleep = 0;
    while (1) {
        LJ::start_request();
        my $did_work = $sclient->work_once;
        exit 0 if $quit_flag;
        next if $did_work;
        $sleep = $interval if ++$sleep > $interval;
        sleep $sleep;
    }
}

1;
