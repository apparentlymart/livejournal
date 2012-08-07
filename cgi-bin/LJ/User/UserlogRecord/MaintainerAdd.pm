package LJ::User::UserlogRecord::MaintainerAdd;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'maintainer_add'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'maintid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return 'Added maintainer ' . $targetu->ljuser_display;
    }

    return "Added maintainer: a bogus user ($targetuserid)";
}

1;
