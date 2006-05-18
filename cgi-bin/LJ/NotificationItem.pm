# This is a class representing a notification that came out of an
# LJ::NotificationInbox. You can tell it to mark itself as
# read/unread, delete it, and get the event that it contains out of
# it.
# Mischa Spiegelmock, 05/2006

package LJ::NotificationItem;
use strict;
use warnings;
use Class::Autouse qw(
                      LJ::NotificationInbox
                      LJ::Event
                      );
use Carp qw(croak);

*new = \&instance;

my %singletons = ();

# parameters: inbox (NotificationInbox this belongs in), qid (id of this item in the inbox),
#             state (state of this item), event (what event this item holds)
sub instance {
    my ($class, %opts) = @_;

    my $inbox = delete $opts{inbox} or croak "No inbox specified";
    my $qid   = delete $opts{qid}   or croak "No queue ID specified";
    my $state = delete $opts{state} or croak "No state specified";
    my $event = delete $opts{event} or croak "No event specified";

    croak "Invalid options" if keys %opts;

    my $u = $inbox->owner or croak "Invalid inbox";

    my $singletonkey = $u->{userid} . ':' . $qid;
    return $singletons{$singletonkey} if $singletons{$singletonkey};

    my $self = {
        u      => $u,
        qid    => $qid,
        inbox  => $inbox,
        state  => $state,
        event  => $event,
    };

    $singletons{$u->{userid}} = $self;

    return bless $self, $class;
}

# returns whose notification this is
*u = \&owner;
sub owner { $_[0]->{u} }

# returns this item's id in the notification queue
sub qid { $_[0]->{qid} }

# returns the inbox that this item is in
sub inbox { $_[0]->{inbox} }

# returns the event that this item refers to
sub event { $_[0]->{event} }

# returns if this event is marked as read
sub read { $_[0]->{state} eq 'R' }

# returns if this event is marked as unread
sub unread { $_[0]->{state} eq 'N' }

# delete this item from its inbox
sub delete {
    my $self = shift;
    my $inbox = $self->inbox;

    return $inbox->delete_from_queue($self);
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
}
