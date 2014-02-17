package LJ::User::UserlogRecord::MaintainerRemove;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'maintainer_remove'}
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
        return LJ::Lang::ml('userlog.action.remove.maintainer', { user => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.remove.maintainer.bogus', { targetuserid => $targetuserid } );
}

1;
