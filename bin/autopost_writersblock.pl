#!/usr/bin/perl
#
# Check if any Writer's Block question had a start time in the last number of
# hours and if so, post them to the writersblock community.
# If writersblock was recently updated don't post, this is to help
# avoid duplicate posts even if this script is rerun or posts are
# inserted manually.

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';
require 'ljfeed.pl';

my $comm = LJ::want_user(LJ::get_userid('writersblock'));
my $u = LJ::want_user(LJ::get_userid('lj_bot'));
my $now = time();
my $ago = $now - (3600 * 13); # X hours = 13

die "Community doesn't exist" unless LJ::isu($comm);
die "User doesn't exist" unless LJ::isu($u);

# check if community has been posted to in the last X hours.
# If so, don't do anything
if ($comm->timeupdate > $ago) {
    print "Community updated recently, don't do anything\n";
    exit;
}

# Find QotDs that started in the last X hours
my $dbh = LJ::get_db_reader()
    or die "Error: no database";
my $sth = $dbh->prepare("SELECT * FROM qotd WHERE time_start > ? AND " .
                        "time_start < ? AND active='Y' ORDER BY time_start");
$sth->execute($ago, $now);
my @rows = ();
while (my $row = $sth->fetchrow_hashref) {
    push @rows, $row;
}

# No QotDs, exit
unless (@rows) {
    print "No new QotDs found, exiting...\n";
    exit;
}

foreach my $row (@rows) {
    print "Posting [" . $row->{qid} . "] " . $row->{subject} . "\n";
    my %req = (
        mode => 'postevent',
        ver => $LJ::PROTOCOL_VER,
        user => $u->user,
        usejournal => $comm->user,
        tz => 'guess',
        subject => $row->{subject},
        event => '<lj-template name="qotd" id="' . $row->{qid} . '" />',
        prop_taglist => $row->{tags},
        prop_opt_noemail => 1,
    );

    my %res;
    my $flags = { noauth => 1, u => $u };
    LJ::do_request(\%req, \%res, $flags);
}

print "ALL DONE\n";
