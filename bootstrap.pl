#!/usr/bin/perl
#

use strict;
die "Must set \$LJHOME before running this.\n"
    unless -d $ENV{'LJHOME'};

my $LJHOME = $ENV{'LJHOME'};
my $mode = @ARGV[0];

if ($mode eq "") {

    chdir $LJHOME or die "Couldn't chdir to \$LJHOME directory.\n";

    system("cvs/vcv/bin/vcv --conf=cvs/livejournal/cvs/multicvs.conf -c -s")
	and die "Failed to run vcv ... do you have the cvs/ dir?\n";
    
    print "done.\n";
    exit;
}

if ($mode eq "makerelease") {
    chdir $LJHOME or die;
    my $path = $ENV{'RELDIR'};
    $path .= "/" if $path;
    my @now = localtime;
    my $ct = 0;
    my $file;
    do {
	$file = sprintf("${path}livejournal-%04d%02d%02d%02d.tar.gz", $now[5]+1900, $now[4]+1, $now[3], $ct);
	$ct++;
    } while (-e $file);

    system("tar -zcvf $file README.txt bootstrap.pl cvs") and die;

    print "done.\n";
    exit;
}

die "Unknown mode.\n";
