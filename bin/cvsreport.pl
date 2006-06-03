#!/usr/bin/perl
#
# This is now just a wrapper around the non-LJ-specific multicvs.pl
#

use strict;

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

if (defined $ENV{'FBHOME'} && $ENV{'PWD'} =~ /^$ENV{'FBHOME'}/i) {
    die "You are running this LJ script while working in FBHOME";
}

# be paranoid in production, force --these
my @paranoia;
eval { require "$ENV{LJHOME}/cgi-bin/ljconfig.pl"; };
if ($LJ::IS_LJCOM_PRODUCTION) {
    @paranoia = ('--these');
}

# strip off paths beginning with LJHOME
# (useful if you tab-complete filenames)
$_ =~ s!\Q$ENV{'LJHOME'}\E/?!! foreach (@ARGV);

my @extra;
my $vcv_exe = "multicvs.pl";
if (-e "$ENV{LJHOME}/bin/vcv") {
    $vcv_exe = "vcv";
    @extra = ("--headserver=code.sixapart.com:10000");
}

exec("$ENV{'LJHOME'}/bin/$vcv_exe",
     "--conf=$ENV{'LJHOME'}/cvs/multicvs.conf",
     @extra,
     @paranoia,
     @ARGV);
