#!/usr/bin/perl

my $commit_number = $ARGV[0];

unless ($commit_number) {
    $commit_number = 0;
    for ('livejournal', 'ljcom') {
        my $svninfo = `svn info $ENV{LJHOME}/cvs/$_`;
        my ($infover) = $svninfo =~ /Revision: (\d+)/i;
        $commit_number += $infover;
    }
}


my $ver = $commit_number ? -1.0 / (sqrt($commit_number / 100)) + 1 : 0;

printf STDOUT "%.3f\n", $ver;
