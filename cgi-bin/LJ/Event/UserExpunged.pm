package LJ::Event::UserExpunged;
use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ($class, $u) = @_;
    croak "No $u" unless $u;

    return $class->SUPER::new($u);
}

sub as_string {
    my $self = shift;
    return $self->event_journal->display_username . " has been purged.";
}

sub as_html {
    my $self = shift;
    return $self->event_journal->ljuser_display . " has been purged.";
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->user;
    my $purgedname = $self->event_journal->display_username;

    my $email =
qq {Dear $username,

We've recently purged another set of deleted accounts:

"$purgedname" is now available

To rename your journal, visit the Account Rename Service for more
details:

$LJ::SITEROOT/rename/
};

    return $email;
}

sub as_email_subject {
    my $self = shift;
    return sprintf "$LJ::SITENAMESHORT Notices: A deleted account has been purged";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return "$ljuser has been purged";
}

1;
