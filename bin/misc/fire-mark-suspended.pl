#!/usr/bin/perl
#
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

# fire job for marking entries posted by suspended account

my $action = shift;
my $userid = shift;
die "Usage: fire-mark-suspended.pl suspend|unsuspend userid|username" unless $userid;

unless ($userid =~ /^\d+$/) {
    my $u = LJ::load_user($userid);
    die "Usage: fire-mark-suspended.pl userid|username" unless $u;
    $userid = $u->userid;
}

my $event = $action eq 'suspend' ? 'LJ::Worker::MarkSuspendedEntries::mark' : 'LJ::Worker::MarkSuspendedEntries::unmark';

my $job = TheSchwartz::Job->new_from_array($event, { userid => $userid });
my $sclient = LJ::theschwartz();

die "Cannot get TheSchwartz client" unless $sclient;
die "Cannot make a job" unless $job;
$sclient->insert_jobs($job);

print "Event Fired!\n";
