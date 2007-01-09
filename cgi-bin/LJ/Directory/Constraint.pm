package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);

sub constraints_from_postargs {
    my ($pkg, $postargs) = @_;

    my @ret;
    foreach my $type (qw(Age Location Interest Friend FriendOf JournalType)) {
       my $class = "LJ::DirectorySearch::Constraint::$type";
       my $con = $class->new_from_postargs($postargs) or
           next;
       push @ret, $con;
    }
    return @ret;
}

1;
