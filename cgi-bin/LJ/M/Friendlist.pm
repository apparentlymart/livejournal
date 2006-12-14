package LJ::M::Friendlist;

use strict;
use warnings;

use Carp qw(croak);

our $left_method;
our $right_method;

sub new {
    my $class = shift;
    my $u = shift || die;
    my $self = bless {
        u => $u,
    }, (ref $class || $class);
    return $self;
}

sub friends {
    local $left_method = "_friends_cached";
    local $right_method = "_friendofs_cached";
    &_render;
}

sub friendofs {
    local $left_method = "_friendofs_cached";
    local $right_method = "_friends_cached";
    &_render;
}

sub _render {
    my $self = shift;

    croak "Left method not defined"  unless $left_method;
    croak "Right method not defined" unless $right_method;

    my $left  = $self->$left_method;
    my $right = $self->$right_method;

    my @return;

    foreach my $leftid (map { $_->[1] }
                          sort { $a->[0] cmp $b->[0] }
                          map { [$left->{$_}->display_name, $_] } keys %$left) {
        push @return, {
            u      => $left->{$leftid},
            mutual => $right->{$leftid} ? 1 : 0,
        };
    }

    return @return;
}

sub _friends_cached {
    my $self = shift;
    return $self->{friends} if $self->{friends};
    return $self->{friends} = $self->{u}->friends;
}

sub _friendofs_cached {
    my $self = shift;
    return $self->{friendofs} if $self->{friendofs};
    return $self->{friendofs} = $self->{u}->friendofs;
}

1;
