# This is a class representing a notification that came out of an
# LJ::NotificationInbox. You can tell it to mark itself as
# read/unread, delete it, and get the event that it contains out of
# it.
# Mischa Spiegelmock, 05/2006

package LJ::NotificationItem;
use strict;
use warnings;
no warnings "redefine";

use Class::Autouse qw(
                      LJ::NotificationInbox
                      LJ::Event
                      );
use Carp qw(croak);

*new = \&instance;

# parameters: user, notification inbox id
sub instance {
    my ($class, $u, $qid) = @_;

    my $singletonkey = $u->{userid} . ':' . $qid;

    $u->{_inbox_items} ||= {};
    return $u->{_inbox_items}->{$singletonkey} if $u->{_inbox_items}->{$singletonkey};

    my $self = {
        u       => $u,
        qid     => $qid,
        state   => undef,
        event   => undef,
        when    => undef,
        _loaded => 0,
    };

    $u->{_inbox_items}->{$singletonkey} = $self;

    return bless $self, $class;
}

# returns whose notification this is
*u = \&owner;
sub owner { $_[0]->{u} }

# returns this item's id in the notification queue
sub qid { $_[0]->{qid} }

# returns true if this item really exists
sub valid {
    my $self = shift;

    return undef unless $self->u && $self->qid;
    $self->_load unless $self->{_loaded};

    return $self->event;
}

# returns title of this item
sub title {
    my $self = shift;
    return eval { $self->event->as_html } || $@;
}

# returns contents of this item
sub as_html {
    my $self = shift;
    return eval { $self->event->content } || $@;
}

# returns the event that this item refers to
sub event {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{event};
}

# loads this item
sub _load {
    my $self = shift;

    my $qid = $self->qid;
    my $u = $self->owner;

    return if $self->{_loaded};

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyqueue WHERE userid=? AND qid=?");
    $sth->execute($u->{userid}, $qid);
    die $sth->errstr if $sth->err;

    my $row = $sth->fetchrow_hashref;
    $self->{_loaded} = 1;

    $self->absorb_row($row);
}

# fills in a skeleton item from a database row hashref
sub absorb_row {
    my ($self, $row) = @_;

    $self->{state} = $row->{state};
    $self->{when} = $row->{createtime};

    my $evt = LJ::Event->new_from_raw_params($row->{etypeid},
                                             $row->{journalid},
                                             $row->{arg1},
                                             $row->{arg2});
    $self->{event} = $evt;
}

# returns when this event happened (or got put in the inbox)
sub when_unixtime {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{when};
}

# returns the state of this item
sub _state {
    my $self = shift;

    $self->_load unless $self->{_loaded};

    return $self->{state};
}

# returns if this event is marked as read
sub read { $_[0]->_state eq 'R' }

# returns if this event is marked as unread
sub unread { $_[0]->_state eq 'N' }

# delete this item from its inbox
sub delete {
    my $self = shift;
    my $inbox = $self->owner->NotificationInbox;

    # delete from the inbox so the inbox stays in sync
    my $ret = $inbox->delete_from_queue($self);
    %$self = ();
    return $ret;
}

# mark this item as read
sub mark_read {
    my $self = shift;

    # do nothing if it's already marked as read
    return if $self->read;
    $self->_set_state('R');
}

# mark this item as read
sub mark_unread {
    my $self = shift;

    # do nothing if it's already marked as unread
    return if $self->unread;
    $self->_set_state('N');
}

# sets the state of this item
sub _set_state {
    my ($self, $state) = @_;

    $self->owner->do("UPDATE notifyqueue SET state=? WHERE qid=?", undef, $state, $self->qid)
        or die $self->owner->errstr;
    $self->{state} = $state;

    # expire unread cache
    my $userid = $self->u->id;
    my $memkey = [$userid, "inbox:${userid}-unread_count"];
    LJ::MemCache::delete($memkey);
}
