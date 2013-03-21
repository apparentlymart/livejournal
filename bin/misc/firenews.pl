#!/usr/bin/perl
#
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use LJ;
use LJ::Entry;
use LJ::Event::OfficialPost;
use LJ::Event::SupOfficialPost;

my $url = shift;
die "Usage: firenews.pl url" unless $url;

my $entry = LJ::Entry->new_from_url($url);
die "No entry found for $url" unless $entry;

my $journal = $entry->journal;

my $etype;
$etype = 'OfficialPost'
    if grep { $_ eq $journal->user } @LJ::OFFICIAL_JOURNALS;
$etype = 'SupOfficialPost'
    if grep { $_ eq $journal->user } @LJ::OFFICIAL_SUP_JOURNALS;

die "This is not a news post" unless ($etype);

my $class = "LJ::Event::$etype";

my $evt = $class->new($entry);
my $sclient = LJ::theschwartz({ 'role' => $evt->schwartz_role });
$sclient->insert(TheSchwartz::Job->new(
    'funcname' => 'LJ::Worker::FiredMass',
    'arg' => {
        'evt' => $evt,
    },
));

print "Event Fired!\n";
