package LJ::User::UserlogRecord::SetOwner;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'set_owner'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'ownerid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return 'Set owner to ' . $targetu->ljuser_display;
    }

    return "Set owner to bogus user ($targetuserid)";
}

1;
