package LJ::User::UserlogRecord::EmailChange;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'email_change'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = { 'new' => delete $data{'new'} };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra     = $self->extra_unpacked;
    my $new_email = $extra->{'new'};

    return 'Email address changed to: ' . $self->_format_email($new_email);
}

1;
