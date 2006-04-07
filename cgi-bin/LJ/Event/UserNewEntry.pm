package LJ::Event::UserNewEntry;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->poster, $entry->journalid, $entry->ditemid);
}

sub is_common { 0 }


1;
