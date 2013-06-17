package LJ::NotificationInbox;

use strict;
use warnings;

# External modules
use Carp 'croak';
use Class::Autouse qw{
    LJ::Event LJ::NotificationArchive
    LJ::Event::InboxUserMessageRecvd LJ::Event::JournalNewComment
};

# Internal modules
use LJ::AntiSpam;
use LJ::NotificationItem;

my ($comment_typeid, $rmessage_typeid, $smessage_typeid);

# constructor takes a $u
sub new {
    my ($class, $user) = @_;

    croak 'Invalid args to construct LJ::NotificationInbox' unless $class and $user;
    croak 'Invalid user' unless LJ::isu($user);

    # return singleton from $u if it already exists
    return $LJ::REQ_CACHE_INBOX{'inbox'} if $LJ::REQ_CACHE_INBOX{'inbox'};

    my $self = {
        userid    => $user->id,
        user      => $user,
    };

    $comment_typeid  ||= LJ::Event::JournalNewComment->etypeid;
    $rmessage_typeid ||= LJ::Event::UserMessageRecvd->etypeid;
    $smessage_typeid ||= LJ::Event::UserMessageSent->etypeid;

    return $LJ::REQ_CACHE_INBOX{'inbox'} = bless $self;
}

# returns the user object associated with this queue
*u = \&owner;
sub owner { $_[0]->{'user'} }

# Returns a list of LJ::NotificationItems in this queue.
sub items {
    return @{ $_[0]->{'items'} }
        if $_[0]->{'items'};

    my $user = &owner;

    $_[0]->{'items'} = [map {
        LJ::NotificationItem->new($user, $_);
    } &_load];

    # optimization:
    #   now items are defined ... if any are comment 
    #   objects we'll instantiate those ahead of time
    #   so that if one has its data loaded they will
    #   all benefit from a coalesced load
    &instantiate_singletons;

    return @{ $_[0]->{'items'} };
}

# returns a list of all notification items except for sent user messages
sub all_items {
    grep { $_->{state} ne 'S' } grep { $_->event->class ne "LJ::Event::UserMessageSent" } grep {$_->event} $_[0]->items;
}

# returns a list of friend-related notificationitems
sub friend_items {
    my @friend_events = friend_event_list();

    my %friend_events = map { "LJ::Event::" . $_ => 1 } @friend_events;

    grep { $friend_events{$_->event->class} } grep {$_->event} $_[0]->items;
}

# returns a list of friend-related notificationitems
sub friendplus_items {
    my @friend_events = friendplus_event_list();

    my %friend_events = map { "LJ::Event::" . $_ => 1 } @friend_events;

    grep { $friend_events{$_->event->class} } grep {$_->event} $_[0]->items;
}

# returns a list of non user-messaging notificationitems
sub non_usermsg_items {
    my @usermsg_events = qw(
                           UserMessageRecvd
                           UserMessageSent
                           );

    @usermsg_events = (@usermsg_events, (LJ::run_hook('usermsg_notification_types') || ()));

    my %usermsg_events = map { "LJ::Event::" . $_ => 1 } @usermsg_events;

    grep { !$usermsg_events{$_->event->class} } grep {$_->event} $_[0]->items;
}

# returns a list of non user-message recvd notificationitems
sub usermsg_recvd_items {
    my @events = ( 'UserMessageRecvd' );
    my @items = $_[0]->subset_items(@events);

    @items = grep { $_->{state} ne 'S' } @items if LJ::is_enabled('spam_inbox');

    return @items;
}

# returns a list of non user-message recvd notificationitems
sub usermsg_sent_items {
    $_[0]->subset_items('UserMessageSent');
}

# returns a list of spam notificationitems
sub spam_items {
    grep { $_->{'state'} eq 'S' } $_[0]->subset_items('UserMessageRecvd');
}

sub birthday_items {
    $_[0]->subset_items('Birthday');
}

sub befriended_items {
    $_[0]->subset_items('Befriended');
}

sub entrycomment_items {
    $_[0]->subset_items(entrycomment_event_list());
}

# return a subset of notificationitems
sub subset_items {
    my ($self, @subset) = @_;

    my %subset_events = map { "LJ::Event::" . $_ => 1 } @subset;
    return grep { $subset_events{$_->event->class} } $self->items;
}

# return flagged notifications
sub bookmark_items {
    grep { $_[0]->is_bookmark($_->qid) } $_[0]->items;
}

# return archived notifications
sub archived_items {
    &owner->notification_archive->items;
}

sub count {
    my $count = LJ::MemCacheProxy::get(&_count_memkey);

    return $count
        if defined $count;

    &_load;

    $count = @{ $LJ::REQ_CACHE_INBOX{'events'} };

    LJ::MemCacheProxy::set(&_count_memkey, $count, 86400);

    return $count;
} # count

# returns number of unread items in inbox
sub unread_count {
    my $self = $_[0];

    my $unread = LJ::MemCacheProxy::get(&_unread_memkey);

    return $unread
        if defined $unread;

    &_load;

    $unread = grep {
        'N' eq uc $_->{'state'}
    } @{ $LJ::REQ_CACHE_INBOX{'events'} };

    LJ::MemCacheProxy::set(&_unread_memkey, $unread, 86400);

    return $unread;
} # unread_count

# unread message count
sub unread_message_count {
    &_load;

    return scalar grep {
        'N' eq uc $_->{'state'}
    } grep {
        $_->{'etypeid'} == $rmessage_typeid
    } @{ $LJ::REQ_CACHE_INBOX{'events'} };
} # unread_message_count

# unread message count
sub unread_event_count {
    &_load;

    return scalar grep {
        'N' eq uc $_->{'state'}
    } grep {
        $_->{'etypeid'} != $rmessage_typeid and
        $_->{'etypeid'} != $smessage_typeid
    } @{ $LJ::REQ_CACHE_INBOX{'events'} };
} # unread_msg_count

sub spam_event_count {
     &_load;

    return scalar grep {
        'S' eq $_->{'state'}
    } @{ $LJ::REQ_CACHE_INBOX{'events'} };   
} # spam_event_count

# load the items in this queue
# returns internal items hashref
sub _load {
    &LJ::NotificationItem::_load;

    return
        unless defined wantarray;

    return map $_->{'qid'}, @{ $LJ::REQ_CACHE_INBOX{'events'} };
}

sub instantiate_singletons {
    return 1 unless $LJ::DISABLED{'inbox_controller'};

    foreach (&items) {
        my $event = $_->event() or next;
        my $etypeid = $event->etypeid();

        # instantiate all the comment singletons so that they will all be
        # loaded efficiently later as soon as preload_rows is called on
        # the first comment object
        LJ::Comment->new(
            $event->event_journal,
            jtalkid => $event->{'args'}[0],
        ) if $etypeid == $comment_typeid;

        # instantiate all the message singletons so that they will all be
        # loaded efficiently later as soon as preload_rows is called on
        # the first message object
        LJ::Message->new({
            msgid     => $event->{'args'}[0],
            otherid   => $event->{'args'}[1],
            journalid => $event->{'userid'},
        }) if $etypeid == $rmessage_typeid or $etypeid == $smessage_typeid;
    }

    return 1;
}

sub _memkey {
    my $userid = $_[0]->{'userid'};
    return [$userid, "inbox:$userid"];
}

sub _count_memkey {
    my $userid = $_[0]->{'userid'};
    return [$userid, "inbox:cnt:$userid"];
}

sub _unread_memkey {
    my $userid = $_[0]->{'userid'};
    return [$userid, "inbox:newct:$userid"];
}

sub _bookmark_memkey {
    my $userid = $_[0]->{'userid'};
    return [$userid, "inbox:bookmarks:$userid"];
}

*_events_memkey = \&LJ::NotificationItem::_events_memkey;

# deletes an Event that is queued for this user
# args: Queue ID to remove from queue
sub delete_from_queue {
    my ($self, $item) = @_;

    my $qid = $item->qid();

    croak 'no queueid for queue item passed to delete_from_queue'
        unless int $qid;

    my $user = &owner
        or die 'No user object';

    # Try to remove bookmark first
    $self->remove_bookmark($qid);

    $user->do('DELETE FROM notifyqueue WHERE userid=? AND qid=?', undef, $self->{'userid'}, $qid);

    die $user->errstr
        if $user->err;

    # invalidate caches
    &expire_cache;

    return 1;
}

sub expire_cache {
    my $self = $_[0];

    delete $self->{'items'};

    $self->{'_loaded'} = 0;

    delete $LJ::REQ_CACHE_INBOX{'events'};

    LJ::MemCacheProxy::delete(&_memkey);
    LJ::MemCacheProxy::delete(&_count_memkey);
    LJ::MemCacheProxy::delete(&_unread_memkey);
    LJ::MemCacheProxy::delete(&_events_memkey);
    LJ::MemCacheProxy::delete(&_bookmark_memkey);
}

# This will enqueue an event object
# Returns the enqueued item
sub enqueue {
    my ($self, %opts) = @_;

    my $evt = delete $opts{event};
    my $archive = delete $opts{archive} || 1;
    croak "No event" unless $evt;
    croak "Extra args passed to enqueue" if %opts;

    my $u = &owner or die "No user";

    # if over the max, delete the oldest notification
    my $max = $u->get_cap('inbox_max');
    my $skip = $max - 1; # number to skip to get to max

    if ($max && $self->count >= $max) {

        # Get list of bookmarks and ignore them when checking inbox limits
        my $bmarks = join ',', $self->get_bookmarks_ids;
        my $bookmark_sql = ($bmarks) ? "AND qid NOT IN ($bmarks) " : '';

        my $too_old_qid = $u->selectrow_array
            ("SELECT qid FROM notifyqueue ".
             "WHERE userid=? $bookmark_sql".
             "ORDER BY qid DESC LIMIT $skip,1",
             undef, $u->id);

        if ($too_old_qid) {
            $u->do("DELETE FROM notifyqueue WHERE userid=? AND qid <= ? $bookmark_sql",
                   undef, $u->id, $too_old_qid);
            $self->expire_cache;
        }
    }

    # get a qid
    my $qid = LJ::alloc_user_counter($u, 'Q')
        or die "Could not alloc new queue ID";
    my $spam = 0;

    if ( LJ::is_enabled('spam_inbox') && $evt->etypeid == LJ::Event::UserMessageRecvd->etypeid ) {
        {
            last unless $evt->arg1;
            last unless $evt->userid;

            my $msg = LJ::Message->load({
                msgid     => $evt->arg1,
                journalid => $evt->userid
            });

            last unless $msg;

            my $sender = $msg->other_u;

            last unless $sender;

            my $journal = LJ::load_userid($evt->userid);

            last unless $journal;

            if (LJ::AntiSpam->need_spam_check_inbox($journal, $sender)) {
                my $body    = $msg->body_raw || '';
                my $subject = $msg->subject_raw || '';

                $spam = LJ::AntiSpam->is_spam_inbox_message(
                    $journal, $sender, $subject
                );

                unless ($spam) {
                    $spam = LJ::AntiSpam->is_spam_inbox_message(
                        $journal, $sender, $body
                    );
                }
            }
        }
    }

    my %item = (qid        => $qid,
                userid     => $u->{userid},
                journalid  => $evt->userid,
                etypeid    => $evt->etypeid,
                arg1       => $evt->arg1,
                arg2       => $evt->arg2,
                state      => $spam ? 'S' : $evt->mark_read ? 'R' : 'N',
                createtime => $evt->eventtime_unix || time());

    # insert this event into the notifyqueue table
    $u->do("INSERT INTO notifyqueue (" . join(",", keys %item) . ") VALUES (" .
           join(",", map { '?' } values %item) . ")", undef, values %item)
        or die $u->errstr;

    if ($archive) {
        # insert into the notifyarchive table with State defaulted to space
        $item{state} = ' ';
        $u->do("INSERT INTO notifyarchive (" . join(",", keys %item) . ") VALUES (" .
               join(",", map { '?' } values %item) . ")", undef, values %item)
            or die $u->errstr;
    }

    if ( LJ::Event::UserMessageRecvd->etypeid == $evt->etypeid ) {
        # send notification
        $self->__send_notify({
            'u'         => $u,
            'journal_u' => LJ::want_user($evt->arg2),
            'msgid'     => $evt->arg1,
            'etypeid'   => $evt->etypeid,
        });
    }

    # invalidate memcache
    $self->expire_cache;

    return LJ::NotificationItem->new($u, $qid);
}

sub __send_notify {
    my ($self, $data) = @_;
    my $msgid       = $data->{'msgid'};
    my $u           = $data->{'u'};
    my $journal_u   = $data->{'journal_u'};

    LJ::Event::InboxUserMessageRecvd->new($u, $msgid, $journal_u)->fire;
}

# return true if item is bookmarked
sub is_bookmark {
    my ($self, $qid) = @_;

    # load bookmarks if they don't already exist
    &load_bookmarks
        unless $self->{'bookmarks'};

    return $self->{'bookmarks'}{$qid}? 1 : 0;
}

# populate the bookmark hash
sub load_bookmarks {
    my ($self) = @_;
    my $format = 'N*';

    return scalar keys %{ $self->{'bookmarks'} }
        if $self->{'bookmarks'};

    my $u = &owner;
    my $row = LJ::MemCacheProxy::get(&_bookmark_memkey);

    if ($row) {
        $self->{'bookmarks'}{$_} = 1
            foreach unpack $format, $row;

        &_load;

        my %items = map { $_->{'qid'} => 1 } @{ $LJ::REQ_CACHE_INBOX{'events'} };

        my @obsolete = grep {
            not exists $items{$_}
        } keys %{ $self->{'bookmarks'} };

        return scalar keys %{ $self->{'bookmarks'} }
            unless @obsolete;

        $self->{'bookmarks'} = {};

        $u->do(join(join(',', map '?', @obsolete), 'DELETE FROM notifybookmarks WHERE userid=? AND qid IN (', ')'), undef, $self->{'userid'}, @obsolete);
    }

    my $qids = $u->selectcol_arrayref('SELECT qid FROM notifybookmarks WHERE userid=?', undef, $self->{'userid'});

    die sprintf "Failed to load bookmarks: %s\n", $u->errstr
        if $u->err;

    $self->{'bookmarks'}{$_} = 1
        foreach @$qids;

    $row = pack $format, @$qids;

    LJ::MemCacheProxy::set(&_bookmark_memkey, $row, 86400);

    return scalar keys %{ $self->{'bookmarks'} };
} # load_bookmarks

## returns array of qid of 'bookmarked' messages
sub get_bookmarks_ids {
    my $self = $_[0];
    
    &load_bookmarks
        unless $self->{'bookmarks'};

    return keys %{ $self->{'bookmarks'} };
}

# add a bookmark
sub add_bookmark {
    my ($self, $qid) = @_;

    my $user = &owner;

    return 0
        unless &can_add_bookmark;

    return 1
        if &is_bookmark;

    $user->do('INSERT IGNORE INTO notifybookmarks (userid, qid) VALUES (?, ?)', undef, $self->{'userid'}, $qid);

    die $user->errstr
        if $user->err;

    # Make sure notice is in inbox
    $self->ensure_queued($qid);

    $self->{'bookmarks'}{$qid} = 1;

    LJ::MemCacheProxy::delete(&_bookmark_memkey);

    return 1;
}

# remove bookmark
sub remove_bookmark {
    my ($self, $qid) = @_;

    my $user = &owner;

    return 0
        unless &is_bookmark;

    $user->do('DELETE FROM notifybookmarks WHERE userid=? AND qid=?', undef, $self->{'userid'}, $qid);

    die $user->errstr
        if $user->err;

    delete $self->{'bookmarks'}{$qid};

    LJ::MemCacheProxy::delete(&_bookmark_memkey);

    return 1;
}

# add or remove bookmark based on whether it is already bookmarked
sub toggle_bookmark { &is_bookmark? &remove_bookmark : &add_bookmark }

# return true if can add a bookmark
sub can_add_bookmark {
    my $max = &owner->get_cap('inbox_max');

    return 0 if $max <= &load_bookmarks + 1;
    return 1;
}

sub delete_all {
    my ( $self, $view, %opts ) = @_;
    my @items;

    # Unless in folder 'Bookmarks', don't fetch any bookmarks
    if ( $view eq 'all' ) {
        @items = $self->all_items;
        push @items, $self->usermsg_sent_items;
    } elsif ( $view eq 'usermsg_recvd' ) {
        @items = $self->usermsg_recvd_items;
    } elsif ( $view eq 'friendplus' ) {
        @items = $self->friendplus_items;
        push @items, $self->birthday_items;
        push @items, $self->befriended_items;
    } elsif ( $view eq 'birthday' ) {
        @items = $self->birthday_items;
    } elsif ( $view eq 'befriended' ) {
        @items = $self->befriended_items;
    } elsif ( $view eq 'entrycomment' ) {
        @items = $self->entrycomment_items;
    } elsif ( $view eq 'bookmark' ) {
        @items = $self->bookmark_items;
    } elsif ( $view eq 'usermsg_sent' ) {
        @items = $self->usermsg_sent_items;
    } elsif ( $view eq 'spam' ) {
        @items = $self->spam_items;
    }

    @items = grep { !$self->is_bookmark($_->qid) } @items
        unless $view eq 'bookmark';

    my @ret;
    foreach my $item (@items) {
        push @ret, {qid => $item->qid};
    }

    my $u = &owner;
    my $interface = $opts{'interface'};

    LJ::User::UserlogRecord::InboxMassDelete->create( $u,
        'remote' => $u,
        'items'  => scalar @items,
        'method' => 'delete_all',
        'view'   => $view,
        'via'    => $interface,
    );

    # Delete items
    foreach my $item (@items) {
        if ($opts{spam}) {
            my $msg = $item->event->load_message();
            $msg->mark_as_spam();
        }
        $item->delete;
    }

    return @ret;
}

sub delete_all_from_sender {
    my ( $self, $senderid ) = @_;
    my @items;

    @items = grep { $_->event->class ne "LJ::Event::UserMessageSent" } grep {$_->event} $self->items;

    @items = grep { !$self->is_bookmark($_->qid) } @items;

    my @ret;
    # Delete items
    foreach my $item (@items) {
        next unless $item->event->arg2 == $senderid;
        push @ret, {qid => $item->qid};
        $item->delete;
    }

    return @ret;
}

sub mark_all_read {
    my ( $self, $view ) = @_;
    my @items;

    # Only get items in currently viewed folder and subfolders
    if ( $view eq 'all' ) {
        @items = $self->all_items;
        push @items, $self->usermsg_sent_items;
    } elsif ( $view eq 'usermsg_recvd' ) {
        @items = $self->usermsg_recvd_items;
    } elsif ( $view eq 'friendplus' ) {
        @items = $self->friendplus_items;
        push @items, $self->birthday_items;
        push @items, $self->befriended_items;
    } elsif ( $view eq 'birthday' ) {
        @items = $self->birthday_items;
    } elsif ( $view eq 'befriended' ) {
        @items = $self->befriended_items;
    } elsif ( $view eq 'entrycomment' ) {
        @items = $self->entrycomment_items;
    } elsif ( $view eq 'bookmark' ) {
        @items = $self->bookmark_items;
    } elsif ( $view eq 'usermsg_sent' ) {
        @items = $self->usermsg_sent_items;
    }

    # Mark read
    $_->mark_read foreach @items;
    return @items;
}

# Copy archive notice to inbox
# Needed when bookmarking a notice that only lives in archive
sub ensure_queued {
    my ($self, $qid) = @_;

    my $u = &owner
        or die "No user object";

    my $sth = $u->prepare
        ("SELECT userid, qid, journalid, etypeid, arg1, arg2, state, createtime " .
         "FROM notifyarchive WHERE userid=? AND qid=?");
    $sth->execute($u->{userid}, $qid);
    die $sth->errstr if $sth->err;

    my $row = $sth->fetchrow_hashref;
    if ($row) {
        my %item = (qid        => $row->{qid},
                    userid     => $row->{userid},
                    journalid  => $row->{journalid},
                    etypeid    => $row->{etypeid},
                    arg1       => $row->{arg1},
                    arg2       => $row->{arg2},
                    state      => 'R',
                    createtime => $row->{createtime});

        # insert this event into the notifyqueue table
        $u->do("INSERT IGNORE INTO notifyqueue (" . join(",", keys %item) . ") VALUES (" .
               join(",", map { '?' } values %item) . ")", undef, values %item)
            or die $u->errstr;

        # invalidate memcache
        $self->expire_cache;
    }

    return;
}

# return a count of a subset of notificationitems
sub subset_unread_count {
    my ($self, @subset) = @_;

    my %subset_events = map { "LJ::Event::" . $_ => 1 } @subset;
    my @events = grep { $subset_events{$_->event->class} && $_->unread } grep {$_->event} $self->items;
    return scalar @events;
}

sub all_event_count {
    scalar grep { $_->event->class ne 'LJ::Event::UserMessageSent' && $_->unread } grep { $_->event } $_[0]->items;
}

sub friend_event_count {
    $_[0]->subset_unread_count(friend_event_list());
}

sub friendplus_event_count {
    $_[0]->subset_unread_count(friendplus_event_list());
}

sub entrycomment_event_count {
    $_[0]->subset_unread_count(entrycomment_event_list());
}

sub usermsg_recvd_event_count {
    $_[0]->subset_unread_count('UserMessageRecvd');
}

sub usermsg_sent_event_count {
    $_[0]->subset_unread_count('UserMessageSent');
}


# Methods that return Arrays of Event categories
sub friend_event_list {
    my @events = qw(
                    Befriended
                    InvitedFriendJoins
                    CommunityInvite
                    NewUserpic
                    );
    @events = (@events, (LJ::run_hook('friend_notification_types') || ()));
    return @events;
}

sub friendplus_event_list {
    my @events = qw(
                    Befriended
                    InvitedFriendJoins
                    CommunityInvite
                    NewUserpic
                    NewVGift
                    Birthday
                    );
    @events = (@events, (LJ::run_hook('friend_notification_types') || ()));
    return @events;
}

sub entrycomment_event_list {
    my @events = qw( 
                     JournalNewEntry
                     JournalNewRepost
                     JournalNewComment 
                     );
    return @events;
}

1;
