package LJ::Talk::Author::OpenID;
use strict;

use base qw(LJ::Talk::Author);

sub enabled {
    return LJ::Identity::OpenID->enabled;
}

sub display_params {
    my ($class, $opts) = @_;

    my $remote = LJ::get_remote();
    my $form = $opts->{'form'};
    my $is_identity =    $remote
                      && $remote->is_identity
                      && $remote->identity->short_code eq 'openid';

    my $is_trusted_identity = $is_identity && $remote->is_trusted_identity;

    my %whocheck = (
        'openid'        => $form->{'usertype'} eq 'openid',
        'openid_cookie' => $form->{'usertype'} eq 'openid_cookie'
                                    || $is_identity,
    );

    return {
        'openid_enabled'         => LJ::OpenID->consumer_enabled,
        'is_identity'            => $is_identity,
        'is_trusted_identity'    => $is_trusted_identity,
        'openid_url_default'     => $is_identity
                                    ? $remote->identity->url
                                    : $form->{'openid:url'},
        'oiddo_login_checked'    => $form->{'oiddo_login'}
                                    ? "checked='checked' "
                                    : '',

        'whocheck_openid'        => $whocheck{'openid'},
        'whocheck_openid_cookie' => $whocheck{'openid_cookie'},

        'helpicon_openid'        => LJ::help_icon_html( "openid", " " ),
    };
}

sub want_user_input {
    my ($class, $usertype) = @_;
    return $usertype =~ /^(?:openid|openid_cookie)$/;
}

sub handle_user_input {
    my ($class, $form, $remote, $need_captcha, $errret, $init) = @_;

    return if @$errret;

    my $journalu = $init->{'journalu'};
    my $up; # user posting

    unless (LJ::OpenID->consumer_enabled) {
        push @$errret, "OpenID consumer support is disabled";
        return;
    }

    my $remote_is_openid = $remote &&
                           $remote->is_identity &&
                           $remote->identity->short_code eq 'openid';

    if ($remote_is_openid) {
        return LJ::get_remote();
    }

    # First time through
    my $csr = LJ::OpenID::consumer();
    my $exptype = 'short';
    my $ipfixed = 0;
    my $etime = 0;

    # parse inline login opts
    unless ($form->{'openid:url'}) {
        push @$errret, "No OpenID identity URL entered";
        return;
    }

    # Store the entry
    my $pendcid = LJ::alloc_user_counter($journalu, "C");

    unless ($pendcid) {
        push @$errret, "Unable to allocate pending id";
        return;
    }

    # Since these were gotten from the openid:url and won't
    # persist in the form data
    $form->{'exptype'} = $exptype;
    $form->{'etime'} = $etime;
    $form->{'ipfixed'} = $ipfixed;
    my $penddata = Storable::nfreeze($form);

    unless ($journalu->writer) {
        push @$errret,
            "Unable to get database handle to store pending comment";
        return;
    }

    $journalu->do(qq{
        INSERT INTO pendcomments
        SET jid = ?, pendcid = ?, data = ?, datesubmit = UNIX_TIMESTAMP()
    }, undef, $journalu->id, $pendcid, $penddata);

    if ($journalu->err) {
        push @$errret, $journalu->errstr;
        return;
    }

    my $returl = "$LJ::SITEROOT/talkpost_do.bml?" .
                 'jid=' . $journalu->id . '&' .
                 "pendcid=$pendcid";

    LJ::Identity::OpenID->attempt_login($errret,
        'returl'      => $returl,
        'returl_fail' => $returl . '&failed=1',
    );
}

1;
