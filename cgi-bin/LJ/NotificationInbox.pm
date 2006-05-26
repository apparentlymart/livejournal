# This package is for managing a queue of notifications
# for a user.
# Mischa Spiegelmock, 4/28/06

package LJ::NotificationInbox;

use strict;
use Carp qw(croak);
use Class::Autouse qw (LJ::NotificationItem LJ::Event);

# constructor takes a $u
sub new {
    my ($class, $u) = @_;

    croak "Invalid args to construct LJ::NotificationQueue" unless $class && $u;
    croak "Invalid user" unless LJ::isu($u);

    my $self = {
        u => $u,
    };

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

    my @qids = $self->_load;

    my @items = ();
    foreach my $qid (@qids) {
        push @items, LJ::NotificationItem->new($self->owner, $qid);
    }

    return @items;
}

# load the items in this queue
# returns internal items hashref
sub _load {
    my $self = shift;
    my $daysold = shift;
    my @items = ();

    my $u = $self->u
        or die "No user object";

    # is it memcached?
    my $qids;
    $qids = LJ::MemCache::get($self->_memkey) and return @$qids;
    # is it cached on the user?
    $qids = $u->{_inbox} and return @$qids;

    # not cached, load
    my $daysoldwhere = $daysold ? " AND createtime" : '';

    $u->{_inbox} = [];

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyqueue WHERE userid=?");
    $sth->execute($u->{userid});
    die $sth->errstr if $sth->err;

    while (my $row = $sth->fetchrow_hashref) {
        my $qid = $row->{qid};

        # load this item into process cache so it's ready to go
        my $qitem = LJ::NotificationItem->new($u, $qid);
        $qitem->absorb_row($row);

        push @items, $qid;
    }

    # cache
    $u->{_inbox} = \@items;
    LJ::MemCache::set($self->_memkey, \@items);

    return @items;
}

sub _memkey {
    my $self = shift;
    my $userid = $self->u->{userid};
    return [$userid, "inbox:$userid"];
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

    $u->do("DELETE FROM notifyqueue WHERE qid=?", undef, $qid);
    die $u->errstr if $u->err;

    # invalidate caches
    delete $u->{_inbox};
    LJ::MemCache::delete($self->_memkey);

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

    # invalidate memcache
    LJ::MemCache::delete($self->_memkey);

    # cache new item
    $u->{_inbox} ||= [];
    push @{$u->{_inbox}}, $qid;

    return LJ::NotificationItem->new($u, $qid);
}

1;
