package LJ::FBInterface;

# Is there a current LJ session?
# If so, return info.
sub get_user_info
{
    my ($class, $POST) = @_;

    # try to get a $u from the passed uid or user, falling back to the ljsession cookie
    my $u;
    if ($POST->{uid}) {
        $u = LJ::load_userid($POST->{uid});
    } elsif ($POST->{user}) {
        $u = LJ::load_user($POST->{user});
    } else {
        my $sess = LJ::Session->session_from_fb_cookie;
        $u = $sess->owner if $sess;
    }

    return {} unless $u;

    if ($u->is_renamed) {
        return {
            'user'          => $u->username,
            'renamedto'     => $u->prop('renamedto'),
            'userid'        => $u->userid,
            'statusvis'     => 'R',
            'fb_account'    => 1,
        };
    }

    return {} unless $u->{'journaltype'} =~ /[PI]/;

    my $defaultpic = $u->userpic;

    my %ret = (
               user            => $u->{user},
               userid          => $u->{userid},
               statusvis       => $u->{statusvis},
               can_upload      => $class->can_upload($u),
               gallery_enabled => $class->can_upload($u),
               diskquota       => LJ::get_cap($u, 'disk_quota') * (1 << 20), # mb -> bytes
               fb_account      => LJ::get_cap($u, 'fb_account'),
               fb_usage        => LJ::Blob::get_disk_usage($u, 'fotobilder'),
               all_styles      => LJ::get_cap($u, 'fb_allstyles'),
               is_identity     => $u->{journaltype} eq 'I' ? 1 : 0,
               userpic_url     => $defaultpic ? $defaultpic->url : undef,
               lj_can_style    => $u->get_cap('styles') ? 1 : 0,
               userpic_count   => $u->get_userpic_count,
               userpic_quota   => $u->userpic_quota,
               esn             => $u->can_use_esn ? 1 : 0,
               new_messages    => $u->new_message_count,
               directory       => $u->get_cap('directory') ? 1 : 0,
               makepoll        => $u->get_cap('makepoll') ? 1 : 0,
               sms             => $u->can_use_sms ? 1 : 0,
               );

    # when the set_quota rpc call is executed (below), a placholder row is inserted
    # into userblob.  it's just used for livejournal display of what we last heard
    # fotobilder disk usage was, but we need to subtract that out before we report
    # to fotobilder how much disk the user is using on livejournal's end
    $ret{diskused} = LJ::Blob::get_disk_usage($u) - $ret{fb_usage};

    return \%ret unless $POST->{fullsync};

    LJ::fill_groups_xmlrpc($u, \%ret);
    return \%ret;
}

# Forcefully push user info out to FB.
# We use this for cases where we don't want to wait for
# sync cache timeouts, such as user suspensions.
sub push_user_info
{
    my ($class, $uid) = @_;

    $uid = LJ::want_userid($uid);
    return unless $uid;
 
    my $ret = $class->get_user_info({ uid => $uid });

    eval "use XMLRPC::Lite;";
    return if $@;

    return XMLRPC::Lite
        -> proxy("$LJ::FB_SITEROOT/interface/xmlrpc")
        -> call('FB.XMLRPC.update_userinfo', $ret)
        -> result;
}

sub can_upload
{
    my ($class, $u) = @_;

    return LJ::get_cap($u, 'fb_account')
        && LJ::get_cap($u, 'fb_can_upload') ? 1 : 0;
}

1;
