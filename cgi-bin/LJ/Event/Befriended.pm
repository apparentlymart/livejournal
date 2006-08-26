package LJ::Event::Befriended;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;
    foreach ($u, $fromu) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $fromu->{userid});
}

sub is_common { 0 }

sub as_email_subject {
    my ($self, $u) = @_;

    return sprintf "$LJ::SITENAMESHORT Notices: %s has added you as a friend!", $self->friend->display_username;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $user = $u->user;
    my $poster = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $entries = LJ::is_friend($u, $self->friend) ? "" : " public";

    my $email = qq {Hi $user,

$poster has added you to their Friends list. They will now be able to read your$entries entries on their Friends page.

From here, you can:};

    $email .= "
  - Add $poster to your Friends list:
    $LJ::SITEROOT/friends/add.bml?user=$poster"
       unless LJ::is_friend($u, $self->friend);

    $email .= qq {
  - Read $poster\'s journal:
    $journal_url
  - Edit Friends:
    $LJ::SITEROOT/friends/edit.bml
  - Edit Friends groups:
    $LJ::SITEROOT/friends/editgroups.bml};

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $user = $u->ljuser_display;
    my $poster = $self->friend->ljuser_display;
    my $postername = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $entries = LJ::is_friend($u, $self->friend) ? "" : " public";

    my $email = qq {Hi $user,

$poster has added you to their Friends list. They will now be able to read your$entries entries on their Friends page.

From here, you can:
<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$postername\">Add $postername to your Friends list</a></li>"
       unless LJ::is_friend($u, $self->friend);

    $email .= "<li><a href=\"$journal_url\">Read $postername\'s journal</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/edit.bml\">Edit Friends</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/editgroups.bml\">Edit Friends groups</a></li></ul>";

    return $email;
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has added you as a friend.",
                   $self->friend->ljuser_display);
}

sub as_string {
    my $self = shift;
    return sprintf("%s has added you as a friend.",
                   $self->friend->{user});
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal or croak "No user";

    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);

    my $user = $journal_is_owner ? "me" : $journal->ljuser_display;
    return "Someone adds $user as a friend";
}

sub content { '' }

1;
