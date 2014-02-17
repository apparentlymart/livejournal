package LJ::User::UserlogRecord::MaintainerAdd;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'maintainer_add'}
sub group  {'community_admin'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'maintid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return LJ::Lang::ml('userlog.action.add.maintainer', { user => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.add.maintainer.bogus', { targetuserid => $targetuserid } );
}

1;
