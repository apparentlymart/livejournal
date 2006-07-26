package LJ::Event::Befriended;
use strict;
use Scalar::Util qw(blessed);
use Class::Autouse qw(LJ::Entry);
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

sub as_email_subject { 'LiveJournal Friend Request!' }

sub as_email_string {
    my ($self, $u) = @_;

    my @vars = (
                $u->display_username,
                $self->friend->display_username,
                );

    push @vars, ($self->entry->poster->display_username, "$LJ::SITEROOT/friends/add.bml?user=" . $self->friend->name)
        unless LJ::is_friend($u, $self->friend);

    push @vars, $self->friend->profile_url;
    push @vars, "$LJ::SITEROOT/friends/edit.bml";

    return sprintf $self->email_body($u), @vars;
}

sub as_email_html {
    my ($self, $u) = @_;

    my @vars = (
                $u->ljuser_display,
                $self->friend->ljuser_display,
                );

    push @vars, ($self->entry->poster->ljuser_display, "$LJ::SITEROOT/friends/add.bml?user=" . $self->friend->name)
        unless LJ::is_friend($u, $self->friend);

    push @vars, "<a href='$LJ::SITEROOT/friends/edit.bml'>$LJ::SITEROOT/friends/edit.bml</a>";

    my $msg = sprintf $self->email_body($u), @vars;

    return $msg;
}

sub email_body {
    my ($self, $u) = @_;

    my $msg = "Hi %s,

%s has added you to their Friends list.

They will now be able to view your public journal updates on their Friends page.";

    $msg .= "Add your new friend so that you can interact with each other's friends and network!

Click here to add them as your friend:
%s" unless LJ::is_friend($u, $self->friend);

    $msg .= "

To view your current friends list:
%s";
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has added me as a friend.",
                   $self->friend->ljuser_display);
}

sub as_string {
    my $self = shift;
    return sprintf("%s has added me as a friend.",
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
