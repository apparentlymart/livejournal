package LJ::Subscription::GroupSet;

use strict;

use LJ::MemCache;

use LJ::Event;
use LJ::Subscription::Group;
use LJ::Subscription::QuotaError;

my @group_cols = (LJ::Subscription::Group::GROUP_COLS());
my @other_cols = (LJ::Subscription::Group::OTHER_COLS());

use Carp qw(confess cluck);

sub new {
    my ($class, $u) = @_;

    return bless({
        'user' => LJ::want_user($u),
        'groups' => {},
        'total_count' => 0,
        'active_count' => 0,
    }, $class);
}

sub clone {
    my ($self) = @_;

    my $class = ref $self;

    my $ret = $class->new($self->user);

    foreach my $group (values %{$self->{'groups'}}) {
        foreach my $sub (values %{$group->{'subs'}}) {
            $ret->insert_sub($sub);
        }
    }

    return $ret;
}

sub _dbh {
    my ($self) = @_;

    unless ($self->{'dbh'}) {
        $self->{'dbh'} = LJ::get_cluster_master($self->user);
        $self->{'dbh'}->{'RaiseError'} = 1;
    }

    return $self->{'dbh'};
}

sub fetch_for_user {
    my ($class, $u, $filter) = @_;

    $filter ||= sub { 1 };

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;

    my $self = $class->new($u);

    $u = LJ::want_user($u);

    confess "cannot get a user" unless $u;

    my $dbr = LJ::get_cluster_reader($u);
    $dbr->{'RaiseError'} = 1;

    confess "cannot get a database handle" unless $dbr;

    my $group_cols = join(',', @group_cols);
    my $other_cols = join(',', @other_cols);

    my @subs = LJ::Subscription->subscriptions_of_user($u);

    my $lastrow = undef;
    my $lastobj = undef;

    my %counted_active;

    foreach my $sub (@subs) {
        if ($sub->group->is_tracking and $sub->enabled) {
            $self->{'total_count'}++ if $sub->{'ntypeid'} == $inbox_ntypeid;

            $self->{'active_count'}++ if
                $sub->active && !($counted_active{$sub->group->freeze}++);
        }

        next unless $filter->($sub);

        $self->insert_sub($sub);
    }

    if ($u->{'opt_gettalkemail'} eq 'Y') {
        my @virtual_subs = (
            {
                'event' => 'JournalNewComment',
                'journalid' => $u->id,
            },
            {
                'event' => 'CommunityEntryReply',
            },
            {
                'event' => 'CommentReply',
            },
        );

        foreach my $subhash (@virtual_subs) {
            $subhash->{'etypeid'} =
                LJ::Event->event_to_etypeid(delete $subhash->{'event'});
            $subhash->{'journalid'} ||= 0;

            $subhash = {
                %$subhash,
                'userid' => $u->id,
                'is_dirty' => 0,
                'arg1' => 0,
                'arg2' => 0,
                'ntypeid' => LJ::NotificationMethod::Email->ntypeid,
                'createtime' => $u->timecreate,
                'expiretime' => 0,
                'flags' => 0,
            };

            next unless $filter->($subhash);

            $self->find_or_insert_sub(bless($subhash, 'LJ::Subscription'));
        }
    }

    $self->{'filtered_out_active_count'} = $self->{'active_count'};
    foreach my $group ($self->groups) {
        $self->{'filtered_out_active_count'}--
            if $group->active && $group->is_tracking;
    }

    return $self;
}

sub update_active_count {
    my ($self) = @_;

    $self->{'active_count'} = $self->{'filtered_out_active_count'};

    foreach my $group ($self->groups) {
        $self->{'active_count'}++
            if $group->active && $group->is_tracking;
    }
}

sub insert_group {
    my ($self, $subgroup) = @_;

    my $key = $subgroup->freeze;

    $self->{'groups'}->{$key} = $subgroup;
}

sub find_group {
    my ($self, $subgroup) = @_;

    my $key = $subgroup->freeze;

    return undef unless $self->{'groups'}->{$key};
    return $self->{'groups'}->{$key};
}

sub find_or_insert_group {
    my ($self, $subgroup) = @_;

    my $key = $subgroup->freeze;

    $self->{'groups'}->{$key} = $subgroup unless $self->{'groups'}->{$key};
    return $self->{'groups'}->{$key};
}

sub insert_sub {
    my ($self, $sub) = @_;

    $sub->{'userid'} = $self->userid;

    my $groupobj = $self->find_or_insert_group($sub->group);
    $groupobj->insert_sub($sub);
}

sub find_sub {
    my ($self, $sub) = @_;

    $sub->{'userid'} = $self->userid;

    my $groupobj = $self->find_group($sub->group) or return undef;
    return $groupobj->find_sub($sub);
}

sub find_or_insert_sub {
    my ($self, $sub) = @_;

    $sub->{'userid'} = $self->userid;

    my $groupobj = $self->find_or_insert_group($sub->group);
    return $groupobj->find_or_insert_sub($sub);
}

sub groups {
    my ($self) = @_;

    return values %{$self->{'groups'}};
}

sub user {
    my ($self) = @_;

    return $self->{'user'};
}

sub userid {
    my ($self) = @_;

    return $self->user->id;
}

sub extract_groups {
    my ($self, $groups) = @_;

    my @ret;

    foreach my $group (@$groups) {
        $group = { 'event' => $group } if ref $group eq '';

        if ($group->{'event'}) {
            my $event = delete $group->{'event'};

            if ($event =~ /\-u$/) {
                $event =~ s/\-u$//;
                $group->{'journalid'} ||= $self->userid;
            }

            $group->{'etypeid'} ||=
                LJ::Event->event_to_etypeid($event);
        }

        $group->{'userid'} ||= $self->userid;
        $group->{'arg1'} ||= 0;
        $group->{'arg2'} ||= 0;

        $group = bless($group, 'LJ::Subscription::Group') if ref $group eq 'HASH';

        push @ret, $self->find_or_insert_group($group);
    }

    return \@ret;
}

sub convert_old_subs {
    my ($self) = @_;

    my $u = $self->user;

    if ($u->{'opt_gettalkemail'} eq 'Y') {
        my @virtual_subs = (
            {
                'event' => 'JournalNewComment',
                'journalid' => $u->id,
            },
            {
                'event' => 'CommunityEntryReply',
            },
            {
                'event' => 'CommentReply',
            },
        );

        foreach my $subhash (@virtual_subs) {
            $subhash->{'etypeid'} =
                LJ::Event->event_to_etypeid(delete $subhash->{'event'});
            $subhash->{'journalid'} ||= 0;

            $subhash = {
                %$subhash,
                'userid' => $u->id,
                'is_dirty' => 0,
                'arg1' => 0,
                'arg2' => 0,
                'ntypeid' => LJ::NotificationMethod::Email->ntypeid,
                'createtime' => $u->timecreate,
                'expiretime' => 0,
                'flags' => 0,
            };

            my $sub = $self->find_sub(bless($subhash, 'LJ::Subscription'));

            unless ($sub->{'subid'}) {
                $self->_db_insert_sub($sub);
            }
        }

        LJ::update_user($u, {'opt_gettalkemail' => 'N'});
    }
}

sub update {
    my ($self, $newset) = @_;

    my $u = $self->user;

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;

    my $array2hash = sub {
        return map { $_ => 1 } @_;
    };

    my @self_groups = keys %{$self->{'groups'}};
    my @new_groups = keys %{$newset->{'groups'}};

    my %self_groups = $array2hash->(@self_groups);
    my %new_groups = $array2hash->(@new_groups);

    my @added_groups = grep { !$self_groups{$_} } @new_groups;
    my @changed_groups = grep { $self_groups{$_} } @new_groups;
    my @cleaned_groups = grep { !$new_groups{$_} } @self_groups;

    foreach my $gkey (@added_groups) {
        my $group_new = $newset->{'groups'}->{$gkey};

        # easy check: if they didn't specify any notification methods,
        # we shall not create it
        next unless keys %{$group_new->{'subs'}};

        # ensure that the inbox method is in there
        $group_new->ensure_inbox_created if $group_new->is_tracking;

        foreach my $ntypeid (keys %{$group_new->{'subs'}}) {
            my $sub = $group_new->{'subs'}->{$ntypeid};
            $self->_db_insert_sub($sub);
        }
    }

    # cleaned groups are simply changed to have no subscriptions. we're not
    # deleting them from the DB here -- at least, "inbox" ntype indicator sub
    # must stay.
    foreach my $gkey (@cleaned_groups) {
        push @changed_groups, $gkey;
        my %props = map { $_ => $self->{'groups'}->{$gkey}->{$_} } @group_cols;

        $newset->{'groups'}->{$gkey} = bless({
            %props,
            'subs' => {},
        }, 'LJ::Subscription::Group');
    }

    foreach my $gkey (@changed_groups) {
        my $group_old = $self->{'groups'}->{$gkey};

        # if they can't access it, don't touch it at all.
        next unless $group_old->event->available_for_user($self->user);

        my $group_new = $newset->{'groups'}->{$gkey};

        $group_new->ensure_inbox_created if $group_new->is_tracking;

        my %ntypeids = map { $_ => 1 } (
            keys %{$group_old->{'subs'}},
            keys %{$group_new->{'subs'}},
        );

        my @ntypeids;

        # inbox goes first, for quota counting
        push @ntypeids, $inbox_ntypeid if delete $ntypeids{$inbox_ntypeid};
        push @ntypeids, keys %ntypeids;

        foreach my $ntypeid (@ntypeids) {
            my $sub_old = $group_old->{'subs'}->{$ntypeid};
            my $sub_new = $group_new->{'subs'}->{$ntypeid};
            if ($sub_old && $sub_new) {
                # "update" case

                # did they really change it? the only change at this point
                # can be enabling/disabling, so:
                next if $sub_old->{'flags'} == $sub_new->{'flags'};

                # fine, they could tweak old-style subs, let's handle it
                $self->convert_old_subs unless $sub_old->{'subid'};

                $self->_db_update_sub($sub_old->{'subid'}, $sub_new);
            } elsif ($sub_old) {
                # "delete" case

                $self->convert_old_subs unless $sub_old->{'subid'};
                $self->_db_drop_sub($sub_old);
            } elsif ($sub_new) {
                # "insert" case

                $self->_db_insert_sub($sub_new);
            }
        }

        $group_old->{'subs'} = $group_new->{'subs'};
        $self->update_active_count;
    }
}

sub drop_group {
    my ($self, $group) = @_;

    return unless $self->find_group($group);

    my (@sets, @binds);

    foreach my $prop (@group_cols) {
        push @sets, "$prop=?";
        push @binds, $group->{$prop};
    }

    my $sets = join(' AND ', @sets);

    $self->_dbh->do("DELETE FROM subs WHERE $sets", undef, @binds);

    LJ::Subscription->invalidate_cache($self->user);
}

sub _db_collect_sets_binds {
    my ($self, $sub, $cols) = @_;

    $cols ||= [@group_cols, @other_cols];

    my (@sets, @binds);
    foreach my $key (@$cols) {
        next if $key eq 'subid';

        push @sets, "$key=?";
        push @binds, int $sub->{$key};
    }
    my $sets = join(',', @sets);

    return ($sets, @binds);
}

sub _check_can_activate {
    my ($self, $sub) = @_;

    my $group = $self->find_group($sub->group);

    return if
        $group && ($group->active || !$group->enabled);

    return if $self->{'active_count'} < LJ::get_cap($self->user, 'subscriptions');

    die LJ::Subscription::QuotaError::Active->new($self->user);
}

sub _db_insert_sub {
    my ($self, $sub) = @_;

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;

    if ($sub->{'ntypeid'} == $inbox_ntypeid) {
        die LJ::Subscription::QuotaError::Total->new($self->user) if
            $self->{'total_count'} >= LJ::get_cap($self->user, 'subscriptions_total');

        $self->{'total_count'}++ if
            $sub->group->is_tracking;
    }

    $self->_check_can_activate($sub) if $sub->active;

    $sub->{'userid'} ||= $self->user->id;
    my ($sets, @binds) = $self->_db_collect_sets_binds($sub);
    my $subid = LJ::alloc_user_counter($self->user, 'E');

    $self->_dbh->do("INSERT INTO subs SET $sets, subid=?", undef, @binds, $subid);

    LJ::Subscription->invalidate_cache($self->user);
}

sub _db_update_sub {
    my ($self, $subid, $sub) = @_;

    $self->_check_can_activate($sub) if $sub->active;

    my ($sets, @binds) = $self->_db_collect_sets_binds($sub, ['flags']);

    $self->_dbh->do("UPDATE subs SET $sets WHERE userid=? AND subid=?", undef, @binds, $self->user->id, $subid);
}

sub _db_drop_sub {
    my ($self, $sub) = @_;

    my $inbox_ntypeid = LJ::NotificationMethod::Inbox->ntypeid;

    $self->{'total_count'}-- if
        $sub->{'ntypeid'} == $inbox_ntypeid &&
        $sub->group->is_tracking;

    my (@sets, @binds);
    foreach my $prop (@group_cols, 'ntypeid') {
        push @sets, "$prop=?";
        push @binds, $sub->{$prop};
    }
    my $sets = join(' AND ', @sets);

    $self->_dbh->do("DELETE FROM subs WHERE $sets", undef, @binds);
    LJ::Subscription->invalidate_cache($self->user);
}

1;
