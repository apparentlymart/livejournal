package LJ::Directory::Constraint::JournalType;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(journaltype);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless $args->{journaltype}
        && $args->{journaltype} =~ /^\w$/;
    return $pkg->new(journaltype => $args->{journaltype});
}

1;
