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

sub as_string {
    my $self = shift;
    return sprintf("The user %s has invited you to join the community %s.",
                   LJ::load_userid($self->arg1)->ljuser_display,
                   LJ::load_userid($self->arg2)->ljuser_display);
}

sub as_sms {
    my $self = shift;

    return sprintf("The user %s has invited you to join the community %s.",
                   LJ::load_userid($self->arg1)->{user},
                   LJ::load_userid($self->arg2)->{user});

}

sub title {
    return 'I receive an invitation to join a community';
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return $class->title;
}

sub journal_sub_title { 'User' }
sub journal_sub_type  { 'owner' }

package LJ::Error::Event::CommunityInvite;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityInvite passed bogus u object: $self->{u}";
}

1;
