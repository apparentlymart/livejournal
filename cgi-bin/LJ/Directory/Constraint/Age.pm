package LJ::Directory::Constraint::Age;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

use LJ::Directory::SetHandle::Age;

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(from to);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{age_min} || $args->{age_max};
    # TODO: exceptions on under 14, etc.
    return $pkg->new(from => ($args->{age_min} || 14),
                     to   => ($args->{age_max} || 125));
}

sub cached_sethandle {
    my ($self) = @_;
    return $self->sethandle;
}

sub sethandle {
    my ($self) = @_;
    return LJ::Directory::SetHandle::Age->new($self->{from}, $self->{to});
}

sub cache_for { 86400  }

1;
