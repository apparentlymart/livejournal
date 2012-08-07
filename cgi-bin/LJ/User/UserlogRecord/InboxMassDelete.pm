package LJ::User::UserlogRecord::InboxMassDelete;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'inbox_massdel'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'items'};

    $data{'extra'} = {
        'method' => delete $data{'method'},
        'view'   => delete $data{'view'},
        'via'    => delete $data{'via'},
    };

    return %data;
}

sub description {
    my ($self) = @_;

    my $count  = $self->actiontarget;

    my $extra  = $self->extra_unpacked;
    my $method = $extra->{'via'};
    my $view   = $extra->{'view'};

    return "Mass-deleted $count inbox messages via '$method' in '$view'";
}

1;
