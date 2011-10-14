package LJ::NumberUtil;
use strict;
use warnings;

use base qw( Exporter );
our @EXPORT_OK = qw( round );

use POSIX;

use constant ROUND_HALF => 0.50000000000008;

# this is stolen from Math::Round on CPAN
sub round {
    my ($num) = @_;

    if ( $num >= 0 ) {
        return int POSIX::floor( $num  + ROUND_HALF );
    } else {
        return int POSIX::ceil( $num - ROUND_HALF );
    }
}

1;
