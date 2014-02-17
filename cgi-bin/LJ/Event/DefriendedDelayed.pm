package LJ::Event::DefriendedDelayed;

use strict;
use warnings;

use base 'LJ::Event::friendedDelayed';

sub send {
    my $class = shift;
    $class->SUPER::send(del => @_);
}
1;
