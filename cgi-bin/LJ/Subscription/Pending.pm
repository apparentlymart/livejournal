# this class represents a pending subscription, used for presenting to the user
# a subscription that doesn't exist yet

package LJ::Subscription::Pending;
use base 'LJ::Subscription';
use strict;
use warnings;
use Carp qw(croak carp);
use Class::Autouse qw (LJ::Event LJ::NotificationMethod);

sub new {
    my $class = shift;
    my $u = shift;
    my %opts = @_;

    die "No user" unless LJ::isu($u);

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

    $method = 'Inbox' unless $ntypeid || $method;
    if ($method) {
        $ntypeid = LJ::NotificationMethod::ntypeid("LJ::NotificationMethod::$method") or croak "Invalid method: $method";
    }
    croak "No ntypeid" unless $ntypeid;

    my $self = {
        u       => $u,
        journal => $journal,
        etypeid => $etypeid,
        ntypeid => $ntypeid,
        arg1    => $arg1,
        arg2    => $arg2,
    };

    return bless $self, $class;
}

sub delete {}
sub pending { 1 }

sub journal   { $_[0]->{journal}}
sub journalid { $_[0]->{journal}->{userid} }

# overload create because you should never be calling it on this object
# (if you want to turn a pending subscription into a real subscription call "commit")
sub create { die "Create called on LJ::Subscription::Pending" }

sub commit {
    my ($self) = @_;

    return $self->{u}->subscribe(
                         etypeid => $self->{etypeid},
                         ntypeid => $self->{ntypeid},
                         journal => $self->{journal},
                         arg1    => $self->{arg1},
                         arg2    => $self->{arg2},
                         );
}

# class method
sub thaw {
    my ($class, $data, $u) = @_;

    my ($type, $user, $journalid, $etypeid, $ntypeid, $arg1, $arg2) = split('-', $data);

    die "Invalid thawed data" unless $type eq 'pending';

    unless ($u) {
        die "no user" unless $user;
        $u = LJ::get_authas_user($user);
        die "Invalid user $user" unless $u;
    }

    return undef unless $journalid && $etypeid;
    return $class->new(
                       $u,
                       journal => $journalid,
                       ntypeid => $ntypeid,
                       etypeid => $etypeid,
                       arg1    => $arg1,
                       arg2    => $arg2,
                       );
}

# instance method
sub freeze {
    my $self = shift;

    my $user = $self->{u}->{user};
    my $journalid = $self->{journal}->{userid};
    my $etypeid = $self->{etypeid};
    my $ntypeid = $self->{ntypeid};

    my @args = ($user,$journalid,$etypeid,$ntypeid);

    push @args, $self->{arg1} if defined $self->{arg1};
    push @args, $self->{arg2} if defined $self->{arg2};

    return join('-', ('pending', @args));
}



1;
