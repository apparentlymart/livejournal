#!/usr/bin/perl
#
# This is now just a wrapper around the non-LJ-specific multicvs.pl
#

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}

# strip off paths beginning with LJHOME
# (useful if you tab-complete filenames)
$_ =~ s!\Q$ENV{'LJHOME'}\E/?!! foreach (@ARGV);

exit system("$ENV{'LJHOME'}/bin/multicvs.pl", 
            "--conf=$ENV{'LJHOME'}/cvs/multicvs.conf", @ARGV);
