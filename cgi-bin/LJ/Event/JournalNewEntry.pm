package LJ::Event::JournalNewEntry;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $entry) = @_;
    croak 'Not an LJ::Entry' unless blessed $entry && $entry->isa("LJ::Entry");
    return $class->SUPER::new($entry->journal, $entry->ditemid);
}

sub is_common { 1 }

sub entry {
    my $self = shift;
    return LJ::Entry->new($self->u, ditemid => $self->arg1);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $ditemid = $self->arg1;
    my $evtju = $self->event_journal;
    return 0 unless $evtju && $ditemid; # TODO: throw error?

    my $entry = LJ::Entry->new($evtju, ditemid => $ditemid);
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # all posts by friends
    return 1 if ! $subscr->journalid && LJ::is_friend($subscr->owner, $self->event_journal);

    # a post on a specific journal
    return LJ::u_equals($subscr->journal, $evtju);
}

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? " titled '" . $entry->subject_text . "'" : '';
    return sprintf("The journal '%s' has a new post$about at: " . $self->entry->url,
                   $self->u->{user});
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub as_html {
    my $self = shift;

    my $journal  = $self->u;
    my $ditemid  = $self->arg1;

    my $entry = LJ::Entry->new($journal, ditemid => $ditemid);
    return "(Invalid entry)" unless $entry && $entry->valid;

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($entry->poster);
    my $url = $entry->url;

    return "New <a href=\"$url\">entry</a> in $ju by $pu.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    return "All entries on any journals on my friends page" unless $journal;

    my $journaluser = $journal->ljuser_display;

    return "All new posts in $journaluser";
}


sub title {
    return 'New post in journal';
}

sub journal_sub_title { 'Journal' }
sub journal_sub_type  { 'any' }

1;
