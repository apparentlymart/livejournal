package LJ::Event::CommunityMantioned;
use strict;
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu, $commu) = @_;
    foreach ($u, $fromu, $commu) {
        LJ::errobj('Event::CommunityMantioned', u => $_)->throw unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $fromu->{userid}, $commu->{userid});
}

sub is_common { 0 }
sub available_for_user  { 1 }

sub is_subscription_visible_to  { 
    my ($class, $u) = @_;
    
    return 0 if ($class->{user}->prop('pingback') eq 'D');
    return 1 if $u->can_manage($class->{user});
    return 0;
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";
    
    return LJ::Lang::ml('event.comm_mantioned', { community => $journal->ljuser_display } );
}

sub is_subscription_ntype_disabled_for {
    my ($self, $ntypeid, $u) = @_;

    return 0 if $ntypeid == LJ::NotificationMethod::Email->ntypeid;
    return 1;
}



package LJ::Error::Event::CommunityMantioned;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommuinityMantioned passed bogus u object: $self->{u}";
}

1;
