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

    my $username = $u->display_username;
    my $purgedname = $self->event_journal->display_username;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:

  - Rename your account
    $LJ::SITEROOT/rename/};

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $purgedname = $self->event_journal->ljuser_display;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:<ul>};

    $email .= "<li><a href='$LJ::SITEROOT/rename/'>Rename your account</a></li>";
    $email .= "</ul>";

    return $email;
}

sub as_email_subject {
    my $self = shift;
    my $username = $self->event_journal->user;

    return sprintf "$LJ::SITENAMESHORT Notices: $username is now available!";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return "$ljuser has been purged";
}

1;
