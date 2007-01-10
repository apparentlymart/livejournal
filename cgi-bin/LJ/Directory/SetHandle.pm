package LJ::Directory::SetHandle;
use strict;
use Carp qw (croak);

use LJ::SetHandle::Inline;

sub new {
    my ($class, @set) = @_;

    my $self = {
        set => \@set,
    };

    return bless $self, $class;
}

# override in subclasses
sub set { @{$_[0]}->{set} }

1;
