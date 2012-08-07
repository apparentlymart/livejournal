package LJ::User::UserlogRecord::BanSet;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'ban_set'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'bannedid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return 'Banned ' . $targetu->ljuser_display;
    }

    return "Banned a bogus user ($targetuserid)";
}

1;
