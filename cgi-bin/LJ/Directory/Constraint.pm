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
use LJ::Directory::Constraint::Test;

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

sub cache_for {
    my $self = shift;
    die "return number of seconds";
}

# digest of canonicalized $self
sub cache_key {
    my $self = shift;
    # sha1 serialize?
}

sub sethandle_if_cached {
    # test cache first, return sethandle if in cache, else undef.
}

sub sethandle {
    # test cache first, return sethandle, or generate set, and return sethandle.

}

1;
