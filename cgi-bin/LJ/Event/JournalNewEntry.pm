# Event that is fired when there is a new post in a journal.
# sarg1 = optional tag id to filter on

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

# TODO: filter by tag (sarg1)
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

    my $entry = $self->entry;
    return "(Invalid entry)" unless $entry && $entry->valid;

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($entry->poster);
    my $url = $entry->url;

    return "New <a href=\"$url\">entry</a> in $ju by $pu.";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    # are we filtering on a tag?
    my $arg1 = $subscr->arg1;
    if ($arg1 eq '?') {
        my $usertags = LJ::Tags::get_usertags($journal);

        my @tagids = sort { $usertags->{$a}->{uses} <=> $usertags->{$b}->{uses} } keys %$usertags;
        my @tagdropdown = map { ($_, $usertags->{$_}->{name}) } @tagids;

        my $dropdownhtml = LJ::html_select({
            name => $subscr->freeze . '.arg1',
        }, @tagdropdown);

        return "all posts tagged $dropdownhtml on " . $journal->ljuser_display;
    } elsif (defined $arg1) {
        my $usertags = LJ::Tags::get_usertags($journal);
        return "all posts tagged $usertags->{$arg1}->{name} on " . $journal->ljuser_display;
    }

    return "All entries on any journals on my friends page" unless $journal;

    my $journaluser = $journal->ljuser_display;

    return "All new posts in $journaluser";
}

# when was this entry made?
sub eventtime_unix {
    my $self = shift;
    my $entry = $self->entry;
    return $entry ? $entry->logtime_unix : $self->SUPER::eventtime_unix;
}

sub title {
    shift;
    my $journal = shift || LJ::get_remote();
    return 'All posts in ' . $journal->ljuser_display;
}

sub journal_sub_title { 'Journal' }
sub journal_sub_type  { 'any' }

1;
