package LJ::Event::CommunityInvite;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu, $commu) = @_;
    foreach ($u, $fromu, $commu) {
        LJ::errobj('Event::CommunityInvite', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $fromu->{userid}, $commu->{userid});
}

sub is_common { 0 }

sub as_email_subject { 'LiveJournal Community Updates!' }

sub as_email_string {
    my ($self, $u) = @_;

    return sprintf qq {Hi %s,

%s has invited you to join a LiveJournal community!

To view all of your current invitations, visit: %s

Click here to view the community details:

%s
}, $u->display_username, $self->inviter->display_username, "$LJ::SITEROOT/manage/invites.bml", $self->comm->profile_url;
}

sub inviter {
    my $self = shift;
    my $u = LJ::load_userid($self->arg1);
    return $u;
}

sub comm {
    my $self = shift;
    my $u = LJ::load_userid($self->arg2);
    return $u;
}

sub as_html {
    my $self = shift;
    return sprintf("The user %s has invited you to join the community %s.",
                   $self->inviter->ljuser_display,
                   $self->comm->ljuser_display);
}

sub as_string {
    my $self = shift;
    return sprintf("The user %s has invited you to join the community %s.",
                   $self->inviter->display_username,
                   $self->comm->display_username);
}

sub as_sms {
    my $self = shift;

    return $self->as_string;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return "I receive an invitation to join a community";
}

package LJ::Error::Event::CommunityInvite;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityInvite passed bogus u object: $self->{u}";
}

1;
