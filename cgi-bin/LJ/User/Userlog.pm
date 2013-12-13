package LJ::User::Userlog;
use strict;
use warnings;

use LJ::User::UserlogRecord;

my %FILTER_TO_ACTION = (
    'Account' => [
        'account_create',
        'accountstatus',
        's2_style_change',
        'upgraded_to_paid_from_trynbuy',
        'vgift_deleted',
        'vgift_row_deleted',
    ],
    'Bans'            => [
        'ban_set',
        'ban_unset',
        'spam_set',
        'spam_unset',
    ],
    'Comments'        => [
        'commentdelete'
    ],
    'Community Admin' => [
        'maintainer_remove',
        'maintainer_add',
        'set_owner'
    ],
    'Entries'         => [
        'delete_delayed_entry',
        'delete_entry',
        'delete_repost',
        'emailpost',
        'mass_privacy_change',
        'moderateentry',
        'restore_entry',
        'tags_manage',
        'twitter_failed',
        'twitter_skipped',
    ],
    'Inbox'           => [
        'inbox_massdel'
    ],
    'Relations' => [
        'addremovefriend',
        'custom_ratings_screen',
        'custom_ratings_unscreen',
        'flush_friends_activities_q',
        'friend_invite_sent',
    ],
    'Scrapbook'       => [
        'album_delete',
        'photo_delete',
        'photo_tag_delete',
        'pics_album_backup_delete',
        'pics_album_restore',
        'pics_photo_backup_delete',
        'pics_photo_restore',
    ],
    'Security'        => [
        'email_change',
        'password_change',
        'password_reset',
        'pwd_reset_req',
        'revoke_validation',
        'suspicious_login_block',
        'suspicious_login_unblock',
    ],
    'Settings' => [
        'changesetting',
    ],
    'Userpics'        => [
        'delete_userpic',
        'userpic_resizer'
    ],
);

sub get_actions_map {
    my @actions = @_;

    return %FILTER_TO_ACTION unless (@actions);

    my %action_to_filter;
    foreach my $key (keys %FILTER_TO_ACTION) {
        foreach (@{$FILTER_TO_ACTION{$key}}) {
            $action_to_filter{$_} = $key;
        }
    }

    my %filter_actions;
    foreach (@actions) {
        my $key = $action_to_filter{$_};
        die "Action \"$_\" is not exist" unless $key;
        push @{$filter_actions{$key}}, $_;
    }

    return %filter_actions;
}

# opts: action, limit
# returns an arrayref of LJ::User::UserlogRecord
sub get_records {
    my ( $class, $u, %opts ) = @_;

    my $limit = int( $opts{'limit'} || 10_000 );
    my $begin = int( $opts{'begin'} || 0      );

    my $dbr = LJ::get_cluster_reader($u);
    my $rows;

    my $actions = $opts{'actions'};
    if ( my $action = $opts{'action'} ) {
        $actions = [$action];
    }
    @$actions = grep {$_} @$actions;
    if (@$actions) {
        my $sql_in = join( ',', ('?') x @$actions );
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? AND action IN ($sql_in) " .
            "ORDER BY logtime DESC LIMIT $begin, $limit",
            { 'Slice' => {} }, $u->userid, @$actions,
        );
    } else {
        $rows = $dbr->selectall_arrayref(
            "SELECT * FROM userlog WHERE userid=? " .
            "ORDER BY logtime DESC LIMIT $begin, $limit",
            { 'Slice' => {} }, $u->userid,
        );
    }

    my @records = map { LJ::User::UserlogRecord->new(%$_) } @$rows;

    # hack: make account_create the last record (pretend that is's always the
    # one with the least timestamp)
    my ( @ret, @account_create_records );
    while ( my $record = shift @records ) {
        if ( $record->action eq 'account_create' ) {
            push @account_create_records, $record;
        } else {
            push @ret, $record;
        }
    }
    push @ret, @account_create_records;
    return \@ret;
}

sub get_records_count {
    my ($u, $actions) = @_;

    my $dbr = LJ::get_cluster_reader($u);

    my $count;
    if ( (ref $actions eq 'ARRAY') && (@$actions) ) {
        my $sql_in = join( ',', ('?') x @$actions );
        $count = $dbr->selectrow_array(
            "SELECT COUNT(*) FROM userlog WHERE userid=? AND action IN ($sql_in)",
            undef,
            $u->userid,
            @$actions
        );
    } else {
        $count = $dbr->selectrow_array('SELECT COUNT(*) FROM userlog WHERE userid=?', undef, $u->userid);
    }

    return $count;
}



1;
