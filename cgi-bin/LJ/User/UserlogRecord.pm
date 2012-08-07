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
    BanSet
    BanUnset
    CustomRatingsScreen
    CustomRatingsUnscreen
    DeleteDelayedEntry
    DeleteEntry
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
    PasswordChange
    PasswordReset
    PasswordResetRequest
    PicsAlbumDelete
    PicsPhotoDelete
    PicsTagDelete
    RevokeEmailValidation
    S2StyleChange
    SetOwner
    SpamSet
    SpamUnset
    TryNBuyUpgrade
    TwitterFailed
    TwitterSkipped
    TwitterSuccess
    UserpicResizer
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

sub translate_create_data {
    my ( $class, %data ) = @_;
    return %data;
}

1;
