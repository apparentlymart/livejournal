#!/usr/bin/perl
#
use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Entry;
use LJ::Event::OfficialPost;

my $url = shift;
die "Usage: firenews.pl url" unless $url;

my $entry = LJ::Entry->new_from_url($url);
die "No entry found for $url" unless $entry;
die "This is not a news post" unless ($entry->journal->is_news);

LJ::Event::OfficialPost->new($entry)->fire;
print "OfficialPost Event fired.\n";
