package LJ::M::Friendlist;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;
    my $u = shift || die;
    my $self = bless {
        u => $u,
    }, (ref $class || $class);
    return $self;
}

sub friends {
    my $self = shift;
    return $self->_process_friendlist('frienduids', 'friendofuids');
}

sub friendofs {
    my $self = shift;
    return $self->_process_friendlist('friendofuids', 'frienduids');
}

sub _process_friendlist {
    my $self = shift;
    my $left_method = shift;
    my $right_method = shift;

    croak "Left method not defined"  unless $left_method;
    croak "Right method not defined" unless $right_method;

    my $u = $self->{u};

    my $left  = $u->$left_method;
    my $right = $u->$right_method;

    my $users;
    {
        my %alluserids = (%$left, %$right);
        $users = LJ::load_userids(keys %alluserids);
    }

    my @return;

    foreach my $leftid (map { $_->[1] }
                        sort { $a->[0] cmp $b->[0] }
                        map { [$users->{$_}->display_name, $_] } @$left) {
        push @return, {
            u      => $users->{$leftid},
            mutual => $right->{$leftid} ? 1 : 0,
        };
    }

    return @return;
}

1;
