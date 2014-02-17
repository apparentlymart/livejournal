package LJ::User::UserlogRecord::BanSet;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'ban_set'}
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
        return LJ::Lang::ml( 'userlog.action.banned', { 'user' => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.banned.bogus', { targetuserid => $targetuserid } );
}

1;
