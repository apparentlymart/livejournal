package LJ::User::InfoHistoryRecord;
use strict;
use warnings;

use base qw( Class::Accessor );
__PACKAGE__->mk_ro_accessors( qw( userid what timechange oldvalue other ) );

sub new {
    my ( $class, $row ) = @_;
    return bless { %$row }, $class;
}

sub user {
    my ($self) = @_;
    return LJ::load_userid( $self->userid );
}

sub timechange_unix {
    my ($self) = @_;
    return LJ::TimeUtil->mysqldate_to_time( $self->timechange );
}

1;
