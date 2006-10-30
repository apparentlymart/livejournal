package LJ::Knob;
use strict;

my %singleton;

sub instance {
    my ($class, $knobname) = @_;
    return $singleton{$knobname} ||= LJ::Knob->new($knobname);
}

sub new {
    my ($class, $knobname) = @_;
    my $self = {
        name => $knobname,
    };
    return bless $self, $class;
}

sub check {
    return rand() < 0.5;
}

1;
