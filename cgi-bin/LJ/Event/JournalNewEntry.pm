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

sub content {
    my ($self, $target) = @_;
    return "(Deleted entry)" unless $self->entry->valid;
    return '(You do not have permission to view this entry)' unless $self->entry->visible_to($target);
    return $self->entry->event_text;
}

sub as_string {
    my $self = shift;
    my $entry = $self->entry;
    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';

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

    my $entry = $self->entry
        or return "(Invalid entry)";

    return "(Deleted entry)" if $entry && ! $entry->valid;

    my $ju = LJ::ljuser($journal);
    my $pu = LJ::ljuser($entry->poster);
    my $url = $entry->url;

    my $about = $entry->subject_text ? ' titled "' . $entry->subject_text . '"' : '';
    my $where = LJ::u_equals($journal, $entry->poster) ? "$pu" : "$pu in $ju";

    return "New <a href=\"$url\">entry</a>$about by $where.";
}

sub as_email_subject {
    my $self = shift;

    if ($self->entry->journal->is_comm) {
        return "$LJ::SITENAMESHORT Notices: There is a new post in " . $self->entry->journal->display_username . "!";
    } else {
        return "$LJ::SITENAMESHORT Notices: " . $self->entry->journal->display_username . " has updated their journal!";
    }
}

sub email_body {
    my ($self, $u) = @_;

    if ($self->entry->journal->is_comm) {
        return "Hi %s,

There is a new post by %s in %s!" . (! LJ::is_friend($u, $self->entry->poster) ? "

You can click here to watch for new updates in %s:
%s" : '') . "

To view the community's profile:
%s

To view the communities that you are a part of:
%s";
    } else {
        return qq "Hi %s,

%s has updated their journal!

You can view the post here:
%s" . (! LJ::is_friend($u, $self->entry->poster) ? "

You can add %s to easily view their $LJ::SITENAMESHORT updates.

Click here to add them as your friend:
%s" : '') . "

To view the user's profile:
%s";
    }
}

sub as_email_string {
    my ($self, $u) = @_;

    my @vars = (
                $u->display_username,
                $self->entry->poster->display_username,
                );

    push @vars, $self->entry->journal->display_username if $self->entry->journal->is_comm;

    push @vars, $self->entry->url unless $self->entry->journal->is_comm;

    push @vars, ($self->entry->journal->display_username, "$LJ::SITEROOT/friends/add.bml?user=" . $self->entry->journal->name)
        unless LJ::is_friend($u, $self->entry->journal);

    push @vars, $self->entry->journal->profile_url;

    push @vars, $u->profile_url if $self->entry->journal->is_comm;

    return sprintf $self->email_body($u), @vars;
}

sub as_email_html {
    my ($self, $u) = @_;

    my @vars = (
                $u->ljuser_display,
                $self->entry->poster->ljuser_display,
                );

    push @vars, $self->entry->journal->ljuser_display if $self->entry->journal->is_comm;

    push @vars, '<a href="' . $self->entry->url . '">' . $self->entry->url . '</a>'
        unless $self->entry->journal->is_comm;

    push @vars, ($self->entry->journal->ljuser_display, "$LJ::SITEROOT/friends/add.bml?user=" . $self->entry->journal->name)
        unless LJ::is_friend($u, $self->entry->journal);

    push @vars, '<a href="' . $self->entry->journal->profile_url . '">' . $self->entry->journal->profile_url . '</a>';

    push @vars, '<a href="' . $u->profile_url . '">' . $u->profile_url . '</a>'  if $self->entry->journal->is_comm;

    return sprintf $self->email_body($u), @vars;
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

    my $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner});
    return () unless $usertags;

    my @tagids = sort { $usertags->{$a}->{name} cmp $usertags->{$b}->{name} } keys %$usertags;
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
            name => $subscr->freeze('arg1'),
        }, @tagdropdown);

        return "All posts tagged $dropdownhtml on " . $journal->ljuser_display;
    } elsif ($arg1) {
        my $usertags = LJ::Tags::get_usertags($journal, {remote => $subscr->owner});
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

1;
