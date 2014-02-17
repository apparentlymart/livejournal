package LJ::Event::BefriendedDelayed;

use strict;
use warnings;

use base 'LJ::Event::friendedDelayed';

sub send {
    my $class = shift;
    $class->SUPER::send(add => @_);
}

1;
