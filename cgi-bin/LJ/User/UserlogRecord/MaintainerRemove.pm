package LJ::User::UserlogRecord::MaintainerRemove;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'maintainer_remove'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'maintid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return 'Removed maintainer ' . $targetu->ljuser_display;
    }

    return "Removed maintainer: a bogus user ($targetuserid)";
}

1;
