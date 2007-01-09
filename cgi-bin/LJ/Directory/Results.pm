package LJ::Directory::Results;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int(delete $args{page_size}) || 100;
    $self->{pages} = int(delete $args{pages}) || 0;
    $self->{page} = int(delete $args{page}) || 1;
    $self->{userids} = delete $args{userids} || [];
    return $self;
}

sub empty_set {
    my ($pkg) = @_;
    return $pkg->new;
}

sub pages {
    my $self = shift;
    $self->{pages};
}

sub userids {
    my $self = shift;
    return @{$self->{userids}};
}

sub users {
    my $self = shift;
    my @uids = $self->userids;
    my $us = LJ::load_userids(@uids);
    return map { $us->{$_} ? ($us->{$_}) : () } @uids;
}

1;
