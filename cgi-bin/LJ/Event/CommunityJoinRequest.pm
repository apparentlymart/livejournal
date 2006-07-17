package LJ::Event::CommunityJoinRequest;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $requestor, $comm) = @_;

    $u =         LJ::want_user($u);
    $requestor = LJ::want_user($requestor);
    $comm =      LJ::want_user($comm);

    foreach ($u, $requestor, $comm) {
        LJ::errobj('Event::CommunityJoinRequest', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $requestor->{userid}, $comm->{userid});
}

sub is_common { 0 }

sub comm {
    my $self = shift;
    return LJ::load_userid($self->arg2);
}

sub requestor {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("The user %s has requested to join the community %s.",
                   $self->requestor->ljuser_display,
                   $self->comm->ljuser_display);
}

sub as_string {
    my $self = shift;
    return sprintf("The user %s has requested to join the community %s.",
                   $self->requestor->display_username,
                   $self->comm->display_username);
}

sub as_email_subject {
    my $self = shift;

    return $self->comm->display_username . " Membership Request by " . $self->requestor->display_username;
}

sub as_email_string {
    my $self = shift;

    return sprintf "Dear %s,\n\n" .
                   "The user \"%s\" has requested to join the \"%s\" community.  If you wish " .
                   "to manage this community's outstanding requests, please click this link:\n\n" .
                   "\t$LJ::SITEROOT/community/pending.bml?comm=%s\n\n" .
                   "You may also ignore this e-mail.  The request to join will expire after a period of 30 days.\n\n" .
                   "Regards,\n$LJ::SITENAME Team\n",

                   $self->u->display_username,
                   $self->requestor->display_username,
                   $self->comm->name;

}

sub as_sms {
    my $self = shift;

    return $self->as_string;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return 'Someone wants to join a community I maintain';
}

package LJ::Error::Event::CommunityJoinRequest;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityJoinRequest passed bogus u object: $self->{u}";
}

1;
