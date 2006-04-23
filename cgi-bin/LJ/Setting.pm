package LJ::Setting;
use strict;
use warnings;

sub pkgkey {
    my $class = shift;
    $class =~ s/::/__/g;
    return $class . "_";
}

1;
