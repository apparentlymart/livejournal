package LJ::Directory::Results;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int(delete $args{page_size}) || 100;
    return $self;
}

sub pages {
    my $self = shift;
    return 20;
}

sub userids {
    my $self = shift;
    return map { 1 } (1..$self->{page_size});
}

sub users {
    my $self = shift;
    my @uids = $self->userids;
    my $us = LJ::load_userids(@uids);
    return map { $us->{$_} ? ($us->{$_}) : () } @uids;
}

1;
