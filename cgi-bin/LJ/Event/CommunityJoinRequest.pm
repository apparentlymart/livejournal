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

    return $class->SUPER::new($u, $requestor->{userid}, $comm->{userid});
}

sub is_common { 0 }

sub as_string {
    my $self = shift;
    return sprintf("The user %s has requested to join the community %s.",
                   LJ::load_userid($self->arg1)->ljuser_display,
                   LJ::load_userid($self->arg2)->ljuser_display);
}

sub as_sms {
    my $self = shift;

    return $self->as_string;
}

sub title {
    return 'Someone wants to join a community I maintain';
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return $class->title;
}

sub journal_sub_title { 'User' }
sub journal_sub_type  { 'owner' }

package LJ::Error::Event::CommunityJoinRequest;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityJoinRequest passed bogus u object: $self->{u}";
}

1;
