package LJ::User::UserlogRecord::SetOwner;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'set_owner'}
sub group  {'community_admin'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'ownerid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return LJ::Lang::ml( 'userlog.action.set.owner', { user => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.set.owner.bogus', { targetuserid => $targetuserid } );
}

1;
