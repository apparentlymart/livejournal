#!/usr/bin/perl
#
# This is now just a wrapper around the non-LJ-specific multicvs.pl
#

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}

exit system("$ENV{'LJHOME'}/bin/multicvs.pl", 
            "--conf=$ENV{'LJHOME'}/cvs/multicvs.conf", @ARGV);
