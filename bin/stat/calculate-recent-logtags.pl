#!/usr/bin/perl

use strict;
use warnings;

use lib "$ENV{'LJHOME'}/cgi-bin";
require 'ljlib.pl';

use Getopt::Long;

my ( $journal_username, $days, $usage );

my $getopt_result = GetOptions(
    'journal=s'     => \$journal_username,
    'days=i'        => \$days,
    'help|usage'    => \$usage
);

if ( $usage || !$getopt_result || !$journal_username || !$days ) {
    usage();
}

my $journalu = LJ::load_user($journal_username);
unless ($journalu) {
    die "$journal_username: no such user\n";
}

my $tags_info = LJ::Tags::calculate_recent_logtags( $journalu, $days );
my $propval = LJ::text_compress( LJ::JSON->to_json($tags_info) );
$journalu->set_prop( 'recent_logtags' => $propval );

sub usage {
    print while ( <DATA> );
    exit;
    return;
}

__DATA__
Usage:

bin/stat/calculate-recent-logtags.pm --journal ohnotheydidnt --days 30
bin/stat/calculate-recent-logtags.pm --help
