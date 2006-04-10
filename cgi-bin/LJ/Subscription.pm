package LJ::Subscription;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    foreach my $k (qw(foo bar baz)) {
        $self->{$k} = delete $opts{$k};
    }
    croak if %opts;
    return $self;
}

1;
