package LJ::Event::DefriendedDelayed;
use strict;
use base 'LJ::Event::friendedDelayed';

sub send {
    my $class = shift;
    $class->SUPER::send(del => @_);
}
1;
