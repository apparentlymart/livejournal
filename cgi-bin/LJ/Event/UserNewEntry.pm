package LJ::Event::UserNewEntry;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use Class::Autouse qw(LJ::Entry);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->poster, $entry->journalid, $entry->ditemid);
}

sub is_common { 0 }

sub entry {
    my $self = shift;
    return LJ::Entry->new(LJ::load_userid($self->arg1),
                          ditemid => $self->arg2);
}

sub as_string {
    my $self = shift;
    return sprintf("User '%s' posted at " . $self->entry->url,
                   $self->u->{user});
}


1;
