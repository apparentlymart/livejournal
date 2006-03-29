#!/usr/bin/perl

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";
use Image::Magick;
use Gearman::Worker;
use Storable;

my $worker = Gearman::Worker->new;
while (1) {
    $worker->job_servers(@LJ::GEARMAN_SERVERS);
    $worker->register_function('lj_upf_resize' => \&lj_upf_resize);
    $worker->work(stop_if => sub { 1 });
    LJ::start_request();
}

sub lj_upf_resize {
    my $job = shift;
    my $args = eval { Storable::thaw($job->arg) } || [];
    return Storable::nfreeze(LJ::_get_upf_scaled(@$args));
}
