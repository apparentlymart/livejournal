#!/usr/bin/perl

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";
use Data::Dumper;
use Getopt::Long;

my $need_help;
my $usage = <<"USAGE";
$0 - script to delete an S2 style/theme from database
Usage:
    $0 <s2lid>
USAGE

GetOptions(
    "help"  => \$need_help
) or die $usage;
die $usage if $need_help || @ARGV!=1 || int($ARGV[0]) ne $ARGV[0];
my $s2lid = shift @ARGV;

{
    print "Are you sure you want to delete layer $s2lid?\n";
    print " See: http://www.livejournal.com/customize/advanced/layerbrowse.bml?id=$s2lid\n";
    print " Type yes in capital letters if you are:\n";
    my $answer = <>;
    chomp $answer;
    exit(0) unless $answer eq 'YES';
}

my $dbh = LJ::get_dbh("master")
 or die;
$dbh->{'RaiseError'} = 1;

foreach my $table (qw( s2checker s2compiled s2compiled2 s2info s2layers s2source s2source_inno
    s2stylelayers s2stylelayers2 s2compiled2 s2stylelayers2 s2compiled2 s2stylelayers2))
{
    my $rv = $dbh->do("DELETE FROM $table WHERE s2lid = ?", undef, $s2lid);
    warn "$rv rows were deleted from $table\n";
}

foreach my $prefix (qw(s2lo s2c s2sl)) {
    LJ::MemCache::delete([ $s2lid, "$prefix:$s2lid" ]);
}

