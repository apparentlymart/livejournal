package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);

sub constraints_from_formargs {
    my ($pkg, $postargs) = @_;

    my @ret;
    foreach my $type (qw(Age Location Interest Friend FriendOf JournalType)) {
       my $class = "LJ::Directory::Constraint::$type";
       my $con = $class->new_from_formargs($postargs) or
           next;
       push @ret, $con;
    }
    return @ret;
}

1;
