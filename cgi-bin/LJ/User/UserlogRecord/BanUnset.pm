package LJ::User::UserlogRecord::BanUnset;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'ban_unset'}
sub group  {'bans'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'bannedid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return LJ::Lang::ml( 'userlog.action.unbanned', { 'user' => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.unbanned.bogus', { targetuserid => $targetuserid } );
}

1;
