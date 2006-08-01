package LJ::Event::NewUserpic;
use strict;
use base 'LJ::Event';
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);

sub new {
    my ($class, $up) = @_;
    croak "No userpic" unless $up;

    return $class->SUPER::new($up->owner, $up->id);
}

sub as_string {
    my $self = shift;

    return $self->event_journal->ljuser_display . " has uploaded a new userpic";
}

sub as_email_string {
    my ($self, $u) = @_;

    my $email = "Hi %s,\n\n%s has updated their userpics!\n\nYou can view them here: %s";

    return sprintf $email, $u->display_username, $self->userpic->owner->display_username,
    "$LJ::SITEROOT/allpics.bml?user=" . $self->userpic->owner->name;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $email = "Hi %s,\n\n%s has updated their userpics!\n\nYou can view them here: %s";

    my $allpics_url = "$LJ::SITEROOT/allpics.bml?user=" . $self->userpic->owner->name;

    return sprintf $email, $u->ljuser_display, $self->userpic->owner->ljuser_display,
    qq {<a href="$allpics_url">$allpics_url</a>};
}

sub userpic {
    my $self = shift;
    my $upid = $self->arg1 or die "No userpic id";
    return eval { LJ::Userpic->new($self->event_journal, $upid) };
}

sub content {
    my $self = shift;
    my $up = $self->userpic;

    if (!$up || !$up->valid) {
        return "(Deleted userpic)";
    }

    return $up->imgtag;
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub as_email_subject {
    my $self = shift;
    return sprintf "LiveJournal Notices: %s Userpic Updates!", $self->event_journal->display_username;
}

sub zero_journalid_subs_means { "friends" }

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    return "One of my friends uploads a new userpic" unless $journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return "$ljuser uploads a new userpic";
}

# only users with the track_user_newuserpic cap can use this
sub available_for_user  {
    my ($class, $u, $subscr) = @_;

    return 0 if ! $u->get_cap('track_user_newuserpic') &&
        $subscr->journalid;

    return 1;
}

1;
