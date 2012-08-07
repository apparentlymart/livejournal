package LJ::User::UserlogRecord::PasswordResetRequest;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'pwd_reset_req'}

my %EmailStateMap = (
    'A' => 'current, validated',
    'T' => 'current, transitioning',
    'N' => 'current, non-validated',
    'P' => 'previously-validated',
);

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = {
        'email'       => delete $data{'email'},
        'email_state' => delete $data{'email_state'},
        'time'        => delete $data{'time'},
    };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra               = $self->extra_unpacked;

    my $email               = $extra->{'email'};
    my $email_display       = $self->_format_email($email);

    my $email_state         = $extra->{'email_state'};
    my $email_state_display = $EmailStateMap{$email_state} || $email_state;

    my $time                = $extra->{'time'};
    my $time_display        = scalar gmtime $time;

    return "Requested a password reset email to $email_display; " .
        "$email_state_display; added on $time_display.";
}

1;
