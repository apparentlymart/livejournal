package LJ::Directory::Constraint::FriendOf;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(userid user);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless ($args->{fro_user} xor $args->{fro_userid});
    return $pkg->new(user   => $args->{fro_user},
                     userid => $args->{fro_userid});
}


1;
