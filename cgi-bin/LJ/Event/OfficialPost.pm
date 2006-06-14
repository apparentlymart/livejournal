package LJ::Event::OfficialPost;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak "No entry" unless $entry;

    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub is_common { 1 }
sub zero_journalid_subs_means { 'all' }

sub as_string {
    my $self = shift;
    my $ditemid = $self->arg1;
    my $entry = LJ::Entry->new($self->event_journal, ditemid => $ditemid) or return "(Invalid entry)";
    return 'There is a new <a href="' . $entry->url . '">post</a> in ' . $entry->journal->ljuser_display;
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub title {
    return 'Someone adds me as a friend';
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return "$LJ::SITENAME makes a new announcement";
}

1;
