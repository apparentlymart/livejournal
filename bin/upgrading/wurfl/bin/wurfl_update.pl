#!/usr/bin/perl
#

use lib "$ENV{'LJHOME'}/cgi-bin";

use LJ::WURFL;
use LJ::WURFL::Parser;
use FindBin;
use File::Spec::Functions qw(catfile);
use Getopt::Long;

my $wurfl_file = "wurfl.xml";
my $store_file = "wireless.stor";
my $datadir = catfile($FindBin::Bin, '..', 'data');

my ($noparse, $test, $verbose) = 3 x 0;

GetOptions(
	"noparse"	=> \$noparse,
	"test"		=> \$test,
	"verbose"	=> \$verbose,
) or die "cannot parse arguments\n";

unless ($noparse) {
	print "Parsing wurfl file.\n" if $verbose;
	my $wurfl = new LJ::WURFL::Parser;
	$wurfl->parse(catfile($datadir, $wurfl_file));
	$wurfl->store(catfile($datadir, $store_file));
	print "Parsed.\n" if $verbose;
}

if ($test) {
    if (eval {require "Devel/Size.pm"}) {
        *total_size = \&Devel::Size::total_size;
    } else {
        *total_size = sub { "unknown" };
    }

	print "Load wireless data.\n";
	my $wurfl = new LJ::WURFL;
	print "Cannot load data file.\n" unless $wurfl->load(catfile($datadir,$store_file));
	print "Size after load: ", total_size(\$wurfl), "\n";
	print "Ready to accept ua strings.\n";

	while(<>) {
		chomp;
		print "result is_mobile(): ", $wurfl->is_mobile($_), "\n";
	}
	print "Size load: ", total_size(\$wurfl), "\n";
}

print "Done.\n" if $verbose;
