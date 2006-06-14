# this class represents a pending subscription, used for presenting to the user
# a subscription that doesn't exist yet

package LJ::Subscription::Pending;
use base 'LJ::Subscription';
use strict;
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

    # force autoload of LJ::Event and it's subclasses
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
        userid  => $u->{userid},
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
    my ($class, $data, $u, $POST) = @_;

    my ($type, $userid, $journalid, $etypeid, $ntypeid, $arg1, $arg2) = split('-', $data);

    die "Invalid thawed data" unless $type eq 'pending';

    unless ($u) {
        my $subuser = LJ::load_userid($userid);
        die "no user" unless $subuser;
        $u = LJ::get_authas_user($subuser);
        die "Invalid user $subuser->{user}" unless $u;
    }

    if ($arg1 && $arg1 eq '?') {
        die "Arg1 option passed without POST data" unless $POST;

        die "No input data for ${data}.arg1" unless defined $POST->{"${data}.arg1"};

        my $arg1value = $POST->{"${data}.arg1"};
        $arg1 = int($arg1value);
    }

    if ($arg2 && $arg2 eq '?') {
        die "Arg2 option passed without POST data" unless $POST;

        die "No input data for ${data}.arg2" unless defined $POST->{"${data}.arg2"};

        my $arg2value = $POST->{"${data}.arg2"};
        $arg2 = int($arg2value);
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

    my $user = $self->{u}->{userid};
    my $journalid = $self->{journal}->{userid};
    my $etypeid = $self->{etypeid};
    my $ntypeid = $self->{ntypeid};

    my @args = ($user,$journalid,$etypeid,$ntypeid);

    push @args, $self->{arg1} if defined $self->{arg1};

    # if arg2 is defined but not arg1, put a zero in arg1
    push @args, 0 if ! defined $self->{arg1} && defined $self->{arg2};

    push @args, $self->{arg2} if defined $self->{arg2};

    return join('-', ('pending', @args));
}



1;
