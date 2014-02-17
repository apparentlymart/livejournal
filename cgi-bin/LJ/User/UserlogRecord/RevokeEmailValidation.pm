package LJ::User::UserlogRecord::RevokeEmailValidation;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'revoke_validation'}
sub group  {'security'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = {
        'email'   => delete $data{'email'},
        'message' => delete $data{'message'},
    };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra   = $self->extra_unpacked;
    my $email   = $extra->{'email'};
    my $message = $extra->{'message'};

    return LJ::Lang::ml( 'userlog.action.revoke.validation', { email => $email, message => $message } );
}

1;
