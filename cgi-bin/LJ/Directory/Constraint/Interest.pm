package LJ::Directory::Constraint::Interest;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

# wants intid
sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(intid int);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless ($args->{int_like} xor $args->{intid});
    return $pkg->new(intid => $args->{intid},
                     int   => $args->{int_like});
}

sub cache_for { 5 * 60 }

1;
