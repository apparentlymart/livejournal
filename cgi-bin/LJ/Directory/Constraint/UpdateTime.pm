package LJ::Directory::Constraint::UpdateTime;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

sub new {
    my ($pkg, $days) = @_;
    my $self = bless { days => $days }, $pkg;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{ut_days};
    return $pkg->new($args->{ut_days});
}


1;
