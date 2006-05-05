# This package is for managing a queue of notifications
# for a user.
# Mischa Spiegelmock, 4/28/06

package LJ::NotificationInbox;

use strict;
use Carp qw(croak);

*new = \&instance;

my %singletons = ();

# constructor takes a $u
sub instance {
    my ($class, $u) = @_;

    croak "Invalid args to construct LJ::NotificationQueue" unless $class && $u;
    croak "Invalid user" unless LJ::isu($u);

    return $singletons{$u->{userid}} if $singletons{$u->{userid}};

    my $self = {
        u      => $u,
        loaded => 0,
        events => {},
    };

    $singletons{$u->{userid}} = $self;

    return bless $self, $class;
}

# returns the user object associated with this queue
sub u {
    my $self = shift;
    return $self->{u};
}

# returns all non-deleted Event objects for this user
# in a hashref of {queueid => event}
# optional arg: daysold = how many days back to retrieve notifications for
sub notifications {
    my $self = shift;
    my $daysold = shift;

    croak "notifications is an object method"
        unless (ref $self) eq __PACKAGE__;

    return $self->_load($daysold);
}

# load the events in this queue
sub _load {
    my $self = shift;
    my $daysold = shift;

    return $self->{events} if $self->{loaded};

    my $u = $self->u
        or die "No user object";

    my $daysoldwhere = $daysold ? " AND createtime" : '';

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " . 
         "FROM notifyqueue WHERE userid=? AND state != 'D'");
    $sth->execute($u->{userid});
    die $sth->errstr if $sth->err;

    while (my $row = $sth->fetchrow_hashref) {
        my $evt = LJ::Event->new_from_raw_params($row->{etypeid},
                                                 $row->{journalid},
                                                 $row->{arg1},
                                                 $row->{arg2});

        next unless $evt;

        # keep track of what qid is associated with this event
        my $qid = $row->{qid};
        $self->{events}->{$qid} = $evt;
    }

    $self->{loaded} = 1;

    return $self->{events};
}

# deletes an Event that is queued for this user
# args: Queue ID to remove from queue
sub delete_from_queue {
    my ($self, $qid) = @_;

    croak "delete_from_queue is an object method"
        unless (ref $self) eq __PACKAGE__;

    croak "no queueid passed to delete_from_queue" unless int($qid);

    my $u = $self->u
        or die "No user object";

    $self->_load;

    # if this event was returned from our queue we should have
    # its qid stored in our events hashref
    delete $self->{events}->{$qid};

    $u->do("DELETE FROM notifyqueue WHERE qid=?", undef, $qid);
    die $u->errstr if $u->err;

    return 1;
}

# This will enqueue an event object
# Returns the queue id
sub enqueue {
    my ($self, %opts) = @_;

    my $evt = delete $opts{event};
    croak "No event" unless $evt;
    croak "Extra args passed to enqueue" if %opts;

    my $u = $self->u or die "No user";

    # get a qid
    my $qid = LJ::alloc_user_counter($u, 'Q')
        or die "Could not alloc new queue ID";

    my %item = (qid        => $qid,
                userid     => $u->{userid},
                journalid  => $evt->u->{userid},
                etypeid    => $evt->etypeid,
                arg1       => $evt->arg1,
                arg2       => $evt->arg2,
                state      => 'N',
                createtime => time());

    # insert this event into the eventqueue table
    $u->do("INSERT INTO notifyqueue (" . join(",", keys %item) . ") VALUES (" .
           join(",", map { '?' } values %item) . ")", undef, values %item)
        or die $u->errstr;

    $self->{events}->{$qid} = $evt;

    return $qid;
}

1;
