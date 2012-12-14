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

    my $singletonkey = $qid;

    $u->{_inbox_items} ||= {};
    return $u->{_inbox_items}->{$singletonkey}
        if defined $u->{_inbox_items}->{$singletonkey} && $u->{_inbox_items}->{$singletonkey};

    my $self = {
        userid  => $u->id,
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
sub owner { LJ::load_userid($_[0]->{userid}) }

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
    return "(Invalid event)" unless $self->event;

    my %opts = @_;
    my $mode = delete $opts{mode};
    croak "Too many args passed to NotificationItem->as_html" if %opts;

    $mode = "html" unless $mode && $LJ::DEBUG{"esn_inbox_titles"};

    if ($mode eq "html") {
        return eval { $self->event->as_html($self->u) } || $@;
    } elsif ($mode eq "im") {
        return eval { $self->event->as_im($self->u) } || $@;
    } elsif ($mode eq "sms") {
        return eval { $self->event->as_sms($self->u) } || $@;
    }
}

# returns contents of this item for user u
sub as_html {
    my $self = shift;
    croak "Too many args passed to NotificationItem->as_html" if scalar @_;
    return "(Invalid event)" unless $self->event;
    return eval { $self->event->content($self->u, $self->_state) } || $@;
}

# returns the event that this item refers to
sub event {
    &_load unless $_[0]->{'_loaded'};

    return $_[0]->{'event'};
}

# loads this item
sub _load {
    my $self = $_[0];

    my $qid = $self->qid;
    my $u = $self->owner;

    return if $self->{_loaded};

    # load info for all the currently instantiated singletons
    # get current singleton qids
    $u->{_inbox_items} ||= {};
    my @qids = map { $_->qid } values %{$u->{_inbox_items}};

    my $bind = join(',', map { '?' } @qids);

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyqueue WHERE userid=? AND qid IN ($bind)");
    $sth->execute($u->id, @qids);
    die $sth->errstr if $sth->err;

    my @items;
    while (my $row = $sth->fetchrow_hashref) {
        my $qid = $row->{qid} or next;
        $u->{_inbox_items}->{$qid} or next;
        push @items => $row;
    }

    ## preload journal objects
    LJ::load_userids( map { $_->{journalid} } @items );

    @items = map {
            my $row = $_;
            my $qid = $row->{qid} or next;
            my $singleton = $u->{_inbox_items}->{$qid} or next;

            $singleton->absorb_row($row);
        } @items;
    
}

# fills in a skeleton item from a database row hashref
sub absorb_row {
    my ($self, $row) = @_;

    $self->{_loaded} = 1;

    $self->{state} = $row->{state};
    $self->{when} = $row->{createtime};

    my $evt = LJ::Event->new_from_raw_params($row->{etypeid},
                                             $row->{journalid},
                                             $row->{arg1},
                                             $row->{arg2});
    $self->{event} = $evt;

    return $self;
}

# returns when this event happened (or got put in the inbox)
sub when_unixtime {
    &_load unless $_[0]->{'_loaded'};

    return $_[0]->{'when'};
}

# returns the state of this item
sub _state {
    &_load unless $_[0]->{'_loaded'};

    return $_[0]->{'state'} || '';
}

# returns if this event is marked as read
sub read {
    return &_state eq 'R';
}

# returns if this event is marked as unread
sub unread {
    return uc &_state eq 'N';
}

# returns if this event was marked as unread by user
sub user_unread {
    return &_state eq 'n';
}

# returns if this event is marked as spam
sub spam {
    return &_state eq 'S';
}

# delete this item from its inbox
sub delete {
    my $self = shift;
    my $inbox = $self->owner->notification_inbox;

    # delete from the inbox so the inbox stays in sync
    my $ret = $inbox->delete_from_queue($self);
    %$self = ();
    return $ret;
}

# mark this item as read
sub mark_read {
    # do nothing if it's already marked as read
    return if &read;

    _set_state($_[0], 'R');
}

# mark this item as read if it was marked as unread by system
sub auto_read {
    &mark_read
        unless &read or &user_unread;
}

# mark this item as read
sub mark_unread {
    # do nothing if it's already marked as unread
    return if &unread;

    _set_state($_[0], 'n');
}

# sets the state of this item
sub _set_state {
    my ($self, $state) = @_;

    $self->owner->do("UPDATE notifyqueue SET state=? WHERE userid=? AND qid=?", undef, $state, $self->owner->id, $self->qid)
        or die $self->owner->errstr;
    $self->{state} = $state;

    # expire unread cache
    my $userid = $self->u->id;
    my $memkey = [$userid, "inbox:newct:${userid}"];
    LJ::MemCache::delete($memkey);
}

1;
