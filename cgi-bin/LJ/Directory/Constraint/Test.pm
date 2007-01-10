package LJ::Directory::Constraint::Test;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(uids);
    croak "unknown args" if %args;
    return $self;
}

1;
