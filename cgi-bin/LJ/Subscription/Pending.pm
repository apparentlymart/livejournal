# this class represents a pending subscription, used for presenting to the user
# a subscription that doesn't exist yet

package LJ::Subscription::Pending;
use base 'LJ::Subscription';
use strict;
use warnings;
use Carp qw(croak);
use Class::Autouse qw (LJ::Event LJ::NotificationMethod);

sub new {
    my ($class, %opts) = @_;

    my $journal = LJ::want_user(delete $opts{journal}) or croak "No journal";
    my $etypeid = delete $opts{etypeid};
    my $ntypeid = delete $opts{ntypeid};
    my $event   = delete $opts{event};
    my $method  = delete $opts{method};
    my $arg1    = delete $opts{arg1};
    my $arg2    = delete $opts{arg2};

    LJ::Event->can('');
    croak "etypeid or event required" unless ($etypeid xor $event);
    if ($event) {
        $etypeid = LJ::Event::etypeid("LJ::Event::$event") or croak "Invalid event: $event";
    }
    croak "No etypeid" unless $etypeid;

    croak "ntypeid or method required" unless ($ntypeid xor $method);
    if ($method) {
        $ntypeid = LJ::NotificationMethod::ntypeid("LJ::NotificationMethod::$method") or croak "Invalid method: $method";
    }
    croak "No ntypeid" unless $ntypeid;


    my $self = {
        journal => $journal,
        etypeid => $etypeid,
        ntypeid => $ntypeid,
        arg1    => $arg1,
        arg2    => $arg2,
    };

    return bless $self, $class;
}

# overload create because you should never be calling it on this object
# (if you want to turn a pending subscription into a real subscription call "commit")
sub create { die "Create called on LJ::Subscription::Pending" }

sub commit {
    my ($self, $u) = @_;

    return $u->subscribe(
                         etypeid => $self->{etypeid},
                         ntypeid => $self->{ntypeid},
                         journal => $self->{journal},
                         arg1    => $self->{arg1},
                         arg2    => $self->{arg2},
                         );
}

sub thaw {
    my ($class, $data) = @_;
    my ($userid, $etypeid, $ntypeid, $arg1, $arg2) = split('-', $data);

    return undef unless $userid && $etypeid;
    return $class->new(
                       journal => $userid,
                       ntypeid => $ntypeid,
                       etypeid => $etypeid,
                       arg1    => $arg1,
                       arg2    => $arg2,
                       );
}

sub freeze {
    my $self = shift;
    my $userid = $self->{journal}->{userid};
    my $arg1 = $self->{arg1} + 0;
    my $arg2 = $self->{arg2} + 0;
    my $etypeid = $self->{etypeid};
    my $ntypeid = $self->{ntypeid};

    return join('-', ($userid, $etypeid, $ntypeid, $arg1, $arg2));
}



1;
