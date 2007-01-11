package LJ::Directory::PackedUserRecord;
use strict;
use Carp qw(croak);

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    foreach my $f (qw(updatetime age journaltype regionid)) {
        $self->{$f}= delete $args{$f};
    }
    croak("Unknown args") if %args;
    return $self;
}

sub packed {
    my $self = shift;
    return pack("NCxCx",
                $self->{updatetime} || 0,
                $self->{age} || 0,
                $self->{regionid} || 0);
}



1;
