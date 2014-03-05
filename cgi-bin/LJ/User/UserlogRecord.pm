package LJ::User::UserlogRecord;
use strict;
use warnings;

use base qw( Class::Accessor );
__PACKAGE__->mk_accessors( qw(
    userid u logtime actiontarget remoteid
    remote ip uniq extra extra_unpacked
) );

my @SubclassesList = map { __PACKAGE__ . '::' . $_ } qw(
    AccountCreate
    AccountStatus
    AddRemoveFriend
    BanSet
    BanUnset
    CommentDelete
    CustomRatingsScreen
    CustomRatingsUnscreen
    ChangeEntryProp
    ChangeEntryText
    ChangeSetting
    DeleteDelayedEntry
    DeleteEntry
    DeleteRepost
    DeleteUserpic
    DeleteVGift
    DeleteVGiftRow
    EmailChange
    EmailPost
    FlushFriendsActivitiesQueue
    FriendInviteSent
    InboxMassDelete
    MaintainerAdd
    MaintainerRemove
    MassPrivacyChange
    ModerateEntry
    PasswordChange
    PasswordReset
    PasswordResetRequest
    PicsAlbumBackupDelete
    PicsAlbumDelete
    PicsAlbumRestore
    PicsPhotoBackupDelete
    PicsPhotoDelete
    PicsPhotoRestore
    PicsTagDelete
    RevokeEmailValidation
    S2StyleChange
    SetOwner
    SpamSet
    SpamUnset
    SuspiciousLoginBlock
    SuspiciousLoginUnblock
    TagsManage
    TryNBuyUpgrade
    TwitterFailed
    TwitterSkipped
    TwitterSuccess
    UserpicResizer
    JournalRestore
);

my %ActionToSubclassMap;

foreach my $subclass (@SubclassesList) {
    my $filename = $subclass . '.pm';
    $filename =~ s{::}{/}g;

    my $load_res = eval { require $filename; 1 };
    unless ($load_res) {
        warn "Couldn't load $subclass: $@";
        next;
    }

    $ActionToSubclassMap{ $subclass->action } = $subclass;
}

sub get_actions_map {
    my @actions = @_;

    my %actions_group_map;
    foreach (values %ActionToSubclassMap) {
        if ( $_->group() ) {
            push @{$actions_group_map{ $_->group() }}, $_->action();
        }
    }

    return %actions_group_map unless (@actions);

    my %action_to_filter;
    foreach my $key (keys %actions_group_map) {
        foreach (@{$actions_group_map{$key}}) {
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

sub get_action_list {
    return keys %ActionToSubclassMap;
}

sub new {
    my ( $class, %data ) = @_;

    $data{'u'}      = LJ::load_userid( $data{'userid'} );
    $data{'remote'} = LJ::load_userid( $data{'remoteid'} )
        if $data{'remoteid'};

    if ( $data{'extra'} && $data{'extra'} ne '' ) {
        my $extra_unpacked = {};
        LJ::decode_url_string( $data{'extra'}, $extra_unpacked );
        $data{'extra_unpacked'} = $extra_unpacked;
    }

    my $subclass = $ActionToSubclassMap{ $data{'action'} } || $class;
    return bless \%data, $subclass;
}

sub action {''}

sub description {
    my ($self) = @_;

    my $action = $self->{'action'};
    my $ret    = "Unknown action $action";

    if ( my $extra = $self->extra ) {
        $ret .= " ($extra)";
    }

    return $ret;
}

sub _format_email {
    my ( $self, $email ) = @_;

    my $cmd = LJ::eurl("finduser $email");
    return qq{<a href="$LJ::SITEROOT/admin/console/?prefill=$cmd">$email</a>};
}

# args: logtime, remote, remote_ip, remote_uniq, extra
# all args are optional
# returns void
sub create {
    my ( $class, $u, %data ) = @_;

    my $action = $class->action;
    die 'no action for LJ::User::UserlogRecord::create' unless $action;

    %data = $class->translate_create_data(%data);

    my $remoteid;
    if ( my $remote = $data{'remote'} || LJ::get_remote() ) {
        $remoteid = $remote->userid;
    }

    my $ip   = $data{'remote_ip'}   || LJ::get_remote_ip();
    my $uniq = $data{'remote_uniq'} || eval { LJ::Request->notes('uniq') };

    my $arg_extra = $data{'extra'} || {};
    my $extra = LJ::encode_url_string($arg_extra);
    my $dbh = LJ::get_cluster_master($u);
    $dbh->do(
        'INSERT INTO userlog ' .
        'SET userid=?, logtime=?, action=?, actiontarget=?, ' .
        'remoteid=?, ip=?, uniq=?, extra=?',
        undef,
        $u->userid, $data{'logtime'} || time, $action, $data{'actiontarget'},
        $remoteid, $ip, $uniq, $extra,
    );

    return;
}

sub create_multi {
    my ( $class, $u, @data ) = @_;

    my $action = $class->action;
    die 'no action for LJ::User::UserlogRecord::create_multi' unless $action;

    my $remote   = LJ::get_remote();
    my $remoteid = $remote && $remote->userid; 
    my $ip       = LJ::get_remote_ip();
    my $uniq     = eval { LJ::Request->notes('uniq') };
    my $time     = time;
    my $userid   = $u->userid;

    my @values;

    foreach my $data (@data) {
        my %data = $class->translate_create_data(%$data);

        push @values, ( $userid,                                                   # userid
                        $data{'logtime'} || $time,                                 # logtime
                        $action,                                                   # action
                        $data{'actiontarget'},                                     # actiontarget
                        ($data{'remote'} && $data{'remote'}->userid) || $remoteid, # remoteid
                        $data{'remote_ip'} || $ip,                                 # ip
                        $data{'remote_uniq'} || $uniq,                             # uniq
                        LJ::encode_url_string($data{'extra'} || {}) );             # extra
    }

    my $values = join ',', map {'(?,?,?,?,?,?,?,?)'} 0..$#data;
    
    my $dbh = LJ::get_cluster_master($u);
    $dbh->do(
        "INSERT INTO userlog (userid, logtime, action, actiontarget, remoteid, ip, uniq, extra)" .
        "VALUES $values",
        undef,
        @values
    );

    return;
}

sub translate_create_data {
    my ( $class, %data ) = @_;
    return %data;
}

1;
