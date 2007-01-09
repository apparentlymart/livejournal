package LJ::Directory::Search;
use strict;
use warnings;
use LJ::Directory::Results;
use LJ::Directory::Constraint;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{page_size} = int(delete $args{page_size}) || 100;
    $self->{page_size} = 25  if $self->{page_size} < 25;
    $self->{page_size} = 200 if $self->{page_size} > 200;

    $self->{page} = int(delete $args{page}) || 1;
    $self->{page} = 1  if $self->{page} < 1;

    $self->{constraints} = delete $args{constraints} || [];
    croak "constraints not a hashref" unless ref $self->{constraints} eq "ARRAY";
    croak "Unknown parameters" if %args;
    return $self;
}

sub add_constraint {
    my ($self, $con) = @_;
    push @{$self->{constraints}}, $con;
}

sub search {
    my $self = shift;
    return LJ::Directory::Results->empty_set unless @{$self->{constraints}};

    # TODO: ship to gearman.  for now, fake it:
    return LJ::Directory::Results->new(page_size => $self->{page_size},
                                       userids   => [ map { (1) } (1..$self->{page_size}) ],
                                       page      => $self->{page});
}

1;
