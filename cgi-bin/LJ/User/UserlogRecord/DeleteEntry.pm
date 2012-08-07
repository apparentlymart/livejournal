package LJ::User::UserlogRecord::DeleteEntry;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'delete_entry'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'actiontarget'} = delete $data{'ditemid'};
    $data{'extra'}        = { 'method' => delete $data{'method'} };

    return %data;
}

sub description {
    my ($self) = @_;

    my $targetid = $self->actiontarget;

    my $extra    = $self->extra_unpacked;
    my $method   = $extra->{'method'};

    return "Deleted entry $targetid via $method";
}

1;
