package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);

use LJ::Directory::Constraint::Location;

sub constraints_from_formargs {
    my ($pkg, $postargs) = @_;

    my @ret;
    foreach my $type (qw(Age Location Interest Friend FriendOf JournalType)) {
       my $class = "LJ::Directory::Constraint::$type";
       my $con = eval { $class->new_from_formargs($postargs) };
       if ($con) {
           push @ret, $con;
       } else {
           #warn "$type: $@\n";
       }

    }
    return @ret;
}

1;
