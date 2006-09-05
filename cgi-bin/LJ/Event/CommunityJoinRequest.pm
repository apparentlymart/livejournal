package LJ::Event::CommunityJoinRequest;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $requestor, $comm) = @_;

    foreach ($u, $requestor, $comm) {
        LJ::errobj('Event::CommunityJoinRequest', u => $_)->throw unless LJ::isu($_);
    }

    # Shouldn't these be method calls? $requestor->id, etc.
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
    return sprintf("The user %s has <a href=\"$LJ::SITEROOT/community/pending.bml?comm=%s\">requested to join</a> the community %s.",
                   $self->requestor->ljuser_display, $self->comm->user,
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
    return sprintf "$LJ::SITENAMESHORT Notices: %s membership request by %s",
      $self->comm->display_username, $self->requestor->display_username;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $maintainer = $u->user;
    my $username = $self->requestor->user;
    my $communityname = $self->comm->user;

    my $email = "Hi $maintainer,

$username has requested to join your community, $communityname.

From here, you can:
  - Manage $communityname\'s membership requests
  $LJ::SITEROOT/community/pending.bml?comm=$communityname
  - Manage your communities
  $LJ::SITEROOT/community/manage.bml";

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $maintainer = $u->ljuser_display;
    my $username = $self->requestor->ljuser_display;
    my $community = $self->comm->ljuser_display;
    my $communityname = $self->comm->user;

    my $email = "Hi $maintainer,

$username has requested to join your community, $community.

From here, you can:<ul>";

    $email .= "<li><a href=\"$LJ::SITEROOT/community/pending.bml?comm=$communityname\">Manage $communityname\'s membership requests</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/community/manage.bml\">Manage your communities</a></li>";
    $email .= "</ul>";

    return $email;

}

sub as_sms {
    my $self = shift;

    return $self->as_string;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return 'Someone requests membership in a community I maintain';
}

package LJ::Error::Event::CommunityJoinRequest;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityJoinRequest passed bogus u object: $self->{u}";
}

1;
