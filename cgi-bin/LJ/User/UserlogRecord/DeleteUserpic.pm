package LJ::User::UserlogRecord::DeleteUserpic;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'delete_userpic'}
sub group  {'userpics'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'extra'} = { 'picid' => delete $data{'picid'} };

    return %data;
}

sub description {
    my ($self) = @_;

    my $extra = $self->extra_unpacked;
    my $picid = $extra->{'picid'};

    return LJ::Lang::ml( 'userlog.action.deleted.userpic', { picid =>$picid } );
}

1;
