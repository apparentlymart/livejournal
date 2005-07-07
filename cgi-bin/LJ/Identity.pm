package LJ::Identity;

use strict;

sub pretty_type {
    my $id = shift;
    return 'OpenID' if $id == 0;
    return 'Invalid identity type';
}

1;
