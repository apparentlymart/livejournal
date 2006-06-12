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

sub matches_filter {
    my ($self, $subscr) = @_;

    my $ditemid = $self->arg1;
    my $evtju = $self->event_journal;
    return 0 unless $evtju && $ditemid; # TODO: throw error?

    my $entry = LJ::Entry->new($evtju, ditemid => $ditemid);
    return 0 unless $entry && $entry->valid; # TODO: throw error?
    return 0 unless $entry->visible_to($subscr->owner);

    # filter by tag?
    my $stagid = $subscr->arg1;
    if ($stagid) {
        my @tags = $entry->tags;

        my $usertaginfo = LJ::Tags::get_usertags($entry->poster, {remote => $subscr->owner});

        my $match = 0;

        if ($usertaginfo) {
            foreach my $tag (@tags) {
                my $entry_tagid;

                while (my ($tagid, $taginfo) = each %$usertaginfo) {
                    next unless $taginfo->{name} eq $tag;
                    $entry_tagid = $tagid;
                    last;
                }
                next unless $entry_tagid == $stagid;

                $match = 1;
                last;
            }
        }

        return 0 unless $match;
    }

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

sub subscription_applicable {
    my ($class, $subscr) = @_;

    return 1 unless $subscr->arg1;

    # subscription is for entries with tsgs.
    # not applicable if user has no tags
    my $journal = $subscr->journal;

    return 1 unless $journal; # ?

    my $usertags = LJ::Tags::get_usertags($journal);

    if ($usertags && (scalar keys %$usertags)) {
        my @unsub = $class->unsubscribed_tags($subscr);
        return (scalar @unsub) ? 1 : 0;
    }

    return 0;
}

# returns list of (hashref of (tagid => name))
sub unsubscribed_tags {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;
    return () unless $journal;

    my $usertags = LJ::Tags::get_usertags($journal);
    return () unless $usertags;

    my @tagids = sort { $usertags->{$a}->{uses} <=> $usertags->{$b}->{uses} } keys %$usertags;
    return grep { $_ } map {
        $subscr->owner->has_subscription(
                                         etypeid => $class->etypeid,
                                         arg1    => $_,
                                         journal => $journal
                                         ) ?
                                         undef : {$_ => $usertags->{$_}->{name}};
    } @tagids;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    # are we filtering on a tag?
    my $arg1 = $subscr->arg1;
    if ($arg1 eq '?') {

        my @unsub_tags = $class->unsubscribed_tags($subscr);

        my @tagdropdown;

        foreach my $unsub_tag (@unsub_tags) {
            while (my ($tagid, $name) = each %$unsub_tag) {
                push @tagdropdown, ($tagid, $name);
            }
        }

        my $dropdownhtml = LJ::html_select({
            name => $subscr->freeze . '.arg1',
        }, @tagdropdown);

        return "All posts tagged $dropdownhtml on " . $journal->ljuser_display;
    } elsif ($arg1) {
        my $usertags = LJ::Tags::get_usertags($journal);
        return "All posts tagged $usertags->{$arg1}->{name} on " . $journal->ljuser_display;
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

1;
