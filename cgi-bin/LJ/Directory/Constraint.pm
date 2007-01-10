package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);

use LJ::Directory::Constraint::Age;
use LJ::Directory::Constraint::Interest;
use LJ::Directory::Constraint::UpdateTime;
use LJ::Directory::Constraint::HasFriend;
use LJ::Directory::Constraint::FriendOf;
use LJ::Directory::Constraint::Location;
use LJ::Directory::Constraint::JournalType;

sub constraints_from_formargs {
    my ($pkg, $postargs) = @_;

    my @ret;
    foreach my $type (qw(Age Location UpdateTime Interest HasFriend FriendOf JournalType)) {
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

sub deserialize {
    my ($pkg, $str) = @_;
    $str =~ s/^(.+?):// or return undef;
    my $type = $1;
    my %args = map { LJ::durl($_) } split(/[=&]/, $str);
    return bless \%args, "LJ::Directory::Constraint::$type";
}

sub serialize {
    my $self = shift;
    my $type = ref $self;
    $type =~ s/^LJ::Directory::Constraint:://;
    return "$type:" . join("&",
                           map { LJ::eurl($_) . "=" . LJ::eurl($self->{$_}) }
                           grep { /^[a-z]/ && $self->{$_} }
                           sort
                           keys %$self);
}

1;
