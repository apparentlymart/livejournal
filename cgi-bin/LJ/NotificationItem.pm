package LJ::NotificationItem;
use strict;
use warnings;
use Carp 'croak';

use Class::Autouse qw{
    LJ::NotificationInbox
    LJ::Event
};

*new = \&instance;

# parameters: user, notification inbox id
sub instance {
    my ($class, $u, $qid) = @_;
    my $singletonkey = $qid;

    my $items = \%LJ::REQ_CACHE_INBOX;

    return $items->{$singletonkey}
        if $items->{$singletonkey};

    my $self = {
        userid  => $u->id,
        user    => $u,
        qid     => $qid,
        state   => undef,
        event   => undef,
        when    => undef,
        _loaded => 0,
    };

    $items->{$singletonkey} = $self;

    return bless $self, $class;
}

# returns whose notification this is
*u = \&owner;
sub owner { $_[0]->{'user'} }

# returns this item's id in the notification queue
sub qid { $_[0]->{'qid'} }

# returns true if this item really exists
sub valid {
    my $self = $_[0];

    return undef unless &owner && $self->qid;
    &_load unless $self->{_loaded};

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

sub _events_memkey {
    my $userid = $_[0]->{'userid'};
    return [$userid, join ':', 'inbox:events', $userid];
}

# Loads this item and all unloaded singletods
sub _load {
    my $self = $_[0];

    return if $self->{'_loaded'};

    my $user  = &owner;
    my $items = \%LJ::REQ_CACHE_INBOX;
    my @items;

    if ($LJ::REQ_CACHE_INBOX{'events'}) {
        @items = @{ $LJ::REQ_CACHE_INBOX{'events'} };
    } else {
        my $key = &_events_memkey;
        my $events = LJ::MemCache::get($key);
        my $format = "(CNNNNNNA)*";
        my @fields = qw{ etypeid userid qid journalid arg1 arg2 createtime state };

        unless (defined $events) {
            my $sth = prepare $user <<"";
                SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime
                FROM notifyqueue WHERE userid=?

            $sth->execute($self->{'userid'});

            die $sth->errstr if $sth->err;

            while (my $row = $sth->fetchrow_hashref()) {
                push @items, $row;
            }

            my $value = pack $format, map { $_ || 0 } map { @{ $_ }{ @fields } } @items;

            LJ::MemCache::set($key, $value, 86400);
        } else {
            my @cache = unpack $format, $events;
            my $i = 0;

            while ($i < @cache) {
                my $item = {};
                @{ $item }{ @fields } = @cache[$i .. $i + $#fields];
                push @items, $item;
                $i += @fields;
            }
        }

        $LJ::REQ_CACHE_INBOX{'events'} = \@items;
    }

    foreach (@items) {
        my $item = $items->{$_->{'qid'}};

        next if not $item or $item->{'_loaded'};

        $item->absorb_row($_)
    }
}

# fills in a skeleton item from a database row hashref
sub absorb_row {
    my ($self, $row) = @_;

    $self->{'_loaded'} = 1;
    $self->{'state'}   = $row->{'state'};
    $self->{'when'}    = $row->{'createtime'};

    $self->{'event'}   = LJ::Event->new_from_raw_params(
        @{ $row }{qw{ etypeid journalid arg1 arg2 }}
    );

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
    my $user = &owner;

    $user->do("UPDATE notifyqueue SET state=? WHERE userid=? AND qid=?", undef, $state, $user->id, $self->qid)
        or die $user->errstr;

    $self->{state} = $state;

    # expire unread cache
    my $userid = $user->id;
    my $memkey = [$userid, "inbox:newct:${userid}"];
    LJ::MemCache::delete($memkey);

    $memkey = &_events_memkey;

    # Expire events cache
    LJ::MemCache::delete($memkey);
}

1;
