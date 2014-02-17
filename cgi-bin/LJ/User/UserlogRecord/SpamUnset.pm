package LJ::User::UserlogRecord::SpamUnset;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'spam_unset'}
sub group  {'bans'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'spammerid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetuserid = $self->actiontarget;
    if ( my $targetu = LJ::load_userid($targetuserid) ) {
        return LJ::Lang::ml('userlog.action.spam.unset', { user => $targetu->ljuser_display } );
    }

    return LJ::Lang::ml( 'userlog.action.spam.unset.bogus', { targetuserid => $targetuserid } );
}

1;
