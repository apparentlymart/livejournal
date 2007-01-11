package LJ::Directory::SetHandle;
use strict;
use Carp qw (croak);

use LJ::Directory::SetHandle::Inline;

sub new {
    my ($class, @set) = @_;

    my $self = {
        set => \@set,
    };

    return bless $self, $class;
}

# override in subclasses
sub new_from_string {
    my ($class, $str) = @_;
    return $class->new(split(',', $str));
}

# override in subclasses
sub set { @{$_[0]->{set}} }

# override in subclasses
sub as_string {
    my $self = shift;
    return join(',', $self->set);
}

1;
