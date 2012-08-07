package LJ::User::UserlogRecord::AccountStatus;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'accountstatus'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = {
        'old' => delete $data{'old'},
        'new' => delete $data{'new'},
    };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra = $self->extra_unpacked;

    my $old_status = $extra->{'old'};
    my $new_status = $extra->{'new'};

    if ( $old_status eq 'V' && $new_status eq 'D' ) {
        return 'Account deleted';
    }

    if ( $old_status eq 'D' && $new_status eq 'V' ) {
        return 'Account undeleted';
    }

    return "Account status changed ($old_status to $new_status)";
}

1;
