package LJ::NewWorker::TheSchwartz;
use strict;

use lib "$ENV{LJHOME}/cgi-bin";
use base "LJ::NewWorker", "Exporter";
require "ljlib.pl";

my  $interval   = 10;
my  $verbose    = 0;

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

sub capabilities    { }

sub on_idle         { }
sub on_afterwork    { }
sub on_prework      { 1 }  # return 1 to proceed and do work

my $sclient;
my $used_role;

sub _init {
    my ($class, $role) = @_;
    $role ||= 'drain';

    die "Already connected to TheSchwartz with role '$used_role'"
        if defined $used_role and $role ne $used_role;

    print STDERR "The Schwartz _init(): init with role $role.\n" if $verbose;

    $sclient = LJ::theschwartz({ role => $role }) or die "Could not get schwartz client";
    $used_role = $role; # save success role
    $sclient->set_verbose($verbose);
}

sub run {
    my $class = shift;
    my $sleep = 0;

    $verbose = $class->verbose;

    print STDERR "The Schwartz run(): init.\n" if $verbose;

    foreach my $cap ($class->capabilities()) {
        my ($classname, $role) = @$cap;
        print STDERR "The Schwartz run(): _init('$role').\n" if $verbose;
        $class->_init($role) unless $sclient;
        print STDERR "The Schwartz run(): can_do('$classname').\n" if $verbose;
        $sclient->can_do($classname);
    }

    $class->_init() unless $sclient;

    print STDERR "The Schwartz run(): init complete, let's do a work.\n" if $verbose;

    my $last_death_check = time();
    while ( ! $class->should_quit()) {
        eval {
            LJ::start_request();
            $class->check_limits();

            my $did_work = 0;
            print STDERR "looking for work..." if $verbose;
            if ($class->on_prework()) {
                $did_work = $sclient->work_once();
                $class->on_afterwork($did_work);
            }
            print STDERR "   did work = ", ($did_work || '') if $verbose;

            return if $class->should_quit();

            if ($did_work) {
                $sleep-- if $sleep > 0;
            } else {
                $class->on_idle();
                $sleep = 10 if ++$sleep > 10;
                sleep $sleep;
            }

            # do request cleanup before we process another job
            LJ::end_request();
        };
        warn $@ if $@;
    }
}

1;
