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
    my $self = shift;

    return sprintf qq {Hi %s,

%s has added you to their Friend's list.

They will now be able to view your public journal updates on their Friends page.  Add your new friend so that you can interact with each other's friends and network!

Click here to add them as your friend:
%s


To view your current friends list:
%s
}, $self->u->display_username, $self->friend->display_username, "$LJ::SITEROOT/friends/add.bml?user=" . $self->friend->name,
"$LJ::SITEROOT/friends/edit.bml";
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
