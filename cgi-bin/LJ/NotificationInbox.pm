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
sub items {
    my $self = shift;

    croak "notifications is an object method"
        unless (ref $self) eq __PACKAGE__;

    my @qids = $self->_load;

    my @items = ();
    foreach my $qid (@qids) {
        push @items, LJ::NotificationItem->new($self->owner, $qid);
    }

    return @items;
}

# returns number of unread items in inbox
# returns a maximum of 1000, if you get 1000 it's safe to
# assume "more than 1000"
sub unread_count {
    my $self = shift;

    # cached unread count
    my $unread = LJ::MemCache::get($self->_unread_memkey);

    return $unread if defined $unread;

    # not cached, load from DB
    my $u = $self->u or die "No user";

    my $sth = $u->prepare("SELECT COUNT(*) FROM notifyqueue WHERE userid=? AND state='N' LIMIT 1000");
    $sth->execute($u->id);
    die $sth->errstr if $sth->err;
    ($unread) = $sth->fetchrow_array;

    # cache it
    LJ::MemCache::set($self->_unread_memkey, $unread, 30 * 60);

    return $unread;
}

# load the items in this queue
# returns internal items hashref
sub _load {
    my $self = shift;

    my $u = $self->u
        or die "No user object";

    # is it memcached?
    my $qids;
    $qids = LJ::MemCache::get($self->_memkey) and return @$qids;

    # not cached, load
    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyqueue WHERE userid=?");
    $sth->execute($u->{userid});
    die $sth->errstr if $sth->err;

    my @items = ();
    while (my $row = $sth->fetchrow_hashref) {
        my $qid = $row->{qid};

        # load this item into process cache so it's ready to go
        my $qitem = LJ::NotificationItem->new($u, $qid);
        $qitem->absorb_row($row);

        push @items, $qitem;
    }

    # sort based on create time
    @items = sort { $a->when_unixtime <=> $b->when_unixtime } @items;

    # get sorted list of ids
    my @item_ids = map { $_->qid } @items;

    # cache
    LJ::MemCache::set($self->_memkey, \@item_ids);

    return @item_ids;
}

sub _memkey {
    my $self = shift;
    my $userid = $self->u->id;
    return [$userid, "inbox:$userid"];
}

sub _unread_memkey {
    my $self = shift;
    my $userid = $self->u->id;
    return [$userid, "inbox:newct:${userid}"];
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

    $u->do("DELETE FROM notifyqueue WHERE userid=? AND qid=?", undef, $u->id, $qid);
    die $u->errstr if $u->err;

    # invalidate caches
    $self->expire_cache;

    return 1;
}

sub expire_cache {
    my $self = shift;
    LJ::MemCache::delete($self->_memkey);
    LJ::MemCache::delete($self->_unread_memkey);
}

# This will enqueue an event object
# Returns the enqueued item
sub enqueue {
    my ($self, %opts) = @_;

    my $evt = delete $opts{event};
    croak "No event" unless $evt;
    croak "Extra args passed to enqueue" if %opts;

    my $u = $self->u or die "No user";

    # check if they are over their limit, if so refuse to add any more
    my $max = $u->get_cap('inbox_max');
    return 0 if $max && $u->notification_inbox->unread_count >= $max;

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
                createtime => $evt->eventtime_unix || time());

    # insert this event into the notifyqueue table
    $u->do("INSERT INTO notifyqueue (" . join(",", keys %item) . ") VALUES (" .
           join(",", map { '?' } values %item) . ")", undef, values %item)
        or die $u->errstr;

    # invalidate memcache
    $self->expire_cache;

    return LJ::NotificationItem->new($u, $qid);
}

1;
