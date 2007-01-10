package LJ::Directory::Constraint;
use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

use Class::Autouse qw (
                       LJ::Directory::SetHandle
                       );

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
    return sha1_hex($self->serialize);
}

# returns cached sethandle if it exists, otherwise undef
sub cached_sethandle {
    my $self = shift;

    return undef;
}

# test cache first, return sethandle, or generate set, and return sethandle.
# TODO: support different sethandle subclasses
sub sethandle {
    my $self = shift;

    my $cached = $self->cached_sethandle;
    return $cached if $cached;

    return LJ::Directory::SetHandle::Inline->new($self->matching_uids);
}

sub matching_uids {
    die "matching_uids called on interface class";
}

1;
