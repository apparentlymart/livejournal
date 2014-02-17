package LJ::User::UserlogRecord::DeleteRepost;
use strict;
use warnings;

use base qw( LJ::User::UserlogRecord );

sub action {'delete_repost'}
sub group  {'entries'}

sub translate_create_data {
    my ( $class, %data ) = @_;

    $data{'journalid'} = delete $data{'journalid'};
    $data{'actiontarget'} = delete $data{'jitemid'};

    return %data;
}

sub description {
    my ($self) = @_;

    my $jitemid = $self->{'actiontarget'};
    return LJ::Lang::ml( 'userlog.action.deleted.repost', { jitemid => $jitemid } );
}

1;
