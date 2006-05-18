# This package is for managing a queue of notifications
# for a user.
# Mischa Spiegelmock, 4/28/06

package LJ::NotificationInbox;

use strict;
use Carp qw(croak);
use Class::Autouse qw (LJ::NotificationItem LJ::Event);

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
        items  => {},
    };

    $singletons{$u->{userid}} = $self;

    return bless $self, $class;
}

# returns the user object associated with this queue
*owner = \&u;
sub u {
    my $self = shift;
    return $self->{u};
}

# Returns a list of LJ::NotificationItems in this queue.
# optional arg: daysold = how many days back to retrieve items for
sub items {
    my $self = shift;
    my $daysold = shift;

    croak "notifications is an object method"
        unless (ref $self) eq __PACKAGE__;

    return values %{$self->_load};
}

# load the items in this queue
# returns internal items hashref
sub _load {
    my $self = shift;
    my $daysold = shift;

    return $self->{items} if $self->{loaded};

    my $u = $self->u
        or die "No user object";

    my $daysoldwhere = $daysold ? " AND createtime" : '';

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyqueue WHERE userid=?");
    $sth->execute($u->{userid});
    die $sth->errstr if $sth->err;

    while (my $row = $sth->fetchrow_hashref) {
        my $qid = $row->{qid};

        # create the inboxitem for this event
        my $qitem = LJ::NotificationItem->new($u, $qid);
        $qitem->absorb_row($row);

        $self->{items}->{$qid} = $qitem;
    }

    $self->{loaded} = 1;

    return $self->{items};
}

# deletes an Event that is queued for this user
# args: Queue ID to remove from queue
sub delete_from_queue {
    my ($self, $qitem) = @_;

    croak "delete_from_queue is an object method"
        unless (ref $self) eq __PACKAGE__;

    my $qid = $qitem->qid;

    croak "no queueid for queue item passed to delete_from_queue" unless int($qid);

    my $u = $self->u
        or die "No user object";

    # if this event was returned from our queue we should have
    # its qid stored in our events hashref
    delete $self->{items}->{$qid} if $self->{items};

    $u->do("DELETE FROM notifyqueue WHERE qid=?", undef, $qid);
    die $u->errstr if $u->err;

    return 1;
}

# This will enqueue an event object
# Returns the enqueued item
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
                createtime => $evt->eventtime_unix || 0);

    # insert this event into the notifyqueue table
    $u->do("INSERT INTO notifyqueue (" . join(",", keys %item) . ") VALUES (" .
           join(",", map { '?' } values %item) . ")", undef, values %item)
        or die $u->errstr;

    $self->{items}->{$qid} = LJ::NotificationItem->new($u, $qid);

    return $self->{items}->{$qid};
}

1;
