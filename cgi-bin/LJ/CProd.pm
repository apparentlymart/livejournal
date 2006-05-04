package LJ::CProd;
# Mostly abstract base class for LiveJournal's contextual product/prodding.
# Let users know about new/old features they can use but never have.
use strict;

# optionally override this:
sub applicable {
    my ($class, $u) = @_;
    # given a user object, is it applicable to advertise
    # this product ($class) to the user?
    return 1;
}

# override this:
sub render {
    my ($class, $u) = @_;
    # given a user, return HTML to promote the product ($class)
    return "Hey $u->{user}, did you know about $class?";
}

# don't override:
sub shortname {
    my $class = shift;
    $class =~ s/^LJ::CProd:://;
    return $class;
}

# don't override, use configuration.
sub weight {
    my $class = shift;
    my $shortname = $class->shortname;
    return $LJ::CPROD_WEIGHT{$shortname} if defined $LJ::CPROD_WEIGHT{$shortname};
    return 1;
}

# returns boolean; if user has dismissed the $class tip
sub has_dismissed {
    my ($class, $u) = @_;
    # TODO: implement
    return 0;
}

sub dismiss {
    my ($class, $u) = @_;
    # TODO: implemnt
}

1;
