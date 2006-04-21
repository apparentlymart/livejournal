package LJ::Event::Befriended;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;
    foreach ($u, $fromu) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $fromu->{userid});
}

sub is_common { 0 }

sub as_string {
    my $self = shift;
    return sprintf("The user '%s' has added '%s' as a friend.",
                   LJ::load_userid($self->arg1)->{user},
                   $self->u->{user});
}

sub title {
    return 'Friend Added';
}

1;
