package LJ::Talk::Author::User;
use strict;

use base qw(LJ::Talk::Author);

sub display_params {
    my ( $class, $opts ) = @_;

    my $remote             = LJ::get_remote();
    my $form               = $opts->{'form'};
    my $journalu           = $opts->{'journalu'};
    my $entry              = LJ::Entry->new( $journalu,
                                             ditemid => $opts->{ditemid} );
    my $is_friend          = LJ::is_friend( $journalu, $remote );
    my $remote_can_comment = $entry->registered_can_comment
        || ( $remote and $is_friend );

    my %whocheck;

    $whocheck{'remote'} = 1
        if $form->{'usertype'} eq 'cookieuser';

    $whocheck{'remote'} = 1
        if $form->{'userpost'} eq $form->{'cookieuser'};

    if ($remote_can_comment) {
        $whocheck{'ljuser'} = 1
            if $form->{'userpost'}
            && $form->{'userpost'} ne $form->{'cookieuser'}
            && $form->{'usertype'} ne 'anonymous';

        $whocheck{'ljuser'} = 1
            if $form->{'usertype'} eq 'user' && !$form->{'userpost'};
    } else {
        $whocheck{'ljuser'} = 1;
    }

    my $ljuser_def = "";
    if ($remote && $remote->is_person) {
        if (   $form->{userpost} ne $form->{cookieuser}
            && $form->{usertype} ne 'anonymous' )
        {
            $ljuser_def = LJ::ehtml( $form->{userpost} );
        }
        else {
            $ljuser_def = $remote->username;
        }
    }
    $ljuser_def = "" unless $remote_can_comment;

    return {
        'css_ljuser_row_id'     => 'ljuser_row'
            . ( $remote_can_comment ? '' : '_cannot' ),
        'username_default'      => $ljuser_def,

        'whocheck_remote'       => $whocheck{'remote'},
        'whocheck_ljuser'       => $whocheck{'ljuser'},
    };
}

sub want_user_input {
    my ($class, $usertype) = @_;
    return $usertype =~ /^(?:user|cookieuser)$/;
}

sub handle_user_input {
    my ($class, $form, $remote, $need_captcha, $errret, $init) = @_;

    my $journalu = $init->{'journalu'};
    my $up; # user posting

    if ($form->{'usertype'} eq "cookieuser") {
        unless ($remote && $remote->username eq $form->{'cookieuser'}) {
            push @$errret,
                LJ::Lang::ml("/htdocs/talkpost_do.bml.error.lostcookie");
            return;
        }

        $init->{'cookie_auth'} = 1;
        return $remote;
    }

    # starting from here, we're provided that $form->{'usertype'} eq "user"
    # (because want_user_input would return false otherwise)

    # test accounts may only comment on other test accounts.
    if (     (grep { $form->{'userpost'} eq $_ } @LJ::TESTACCTS)
         && !(grep { $journalu->username eq $_ } @LJ::TESTACCTS)
         && !$LJ::IS_DEV_SERVER )
    {
        push @$errret,
            LJ::Lang::ml("/htdocs/talkpost_do.bml.error.testacct");
        return;
    }

    unless ($form->{'userpost'}) {
        push @$errret,
            LJ::Lang::ml("/htdocs/talkpost_do.bml.error.nousername");
        return;
    }

    # parse inline login opts
    my ($exptype, $ipfixed);
    if ($form->{'userpost'} =~ s/[!<]{1,2}$//) {
        $exptype = 'long' if index($&, "!") >= 0;
        $ipfixed = LJ::get_remote_ip() if index($&, "<") >= 0;
    }

    $up = LJ::load_user($form->{'userpost'});
    unless ($up) {
        push @$errret,
            LJ::Lang::ml("/htdocs/talkpost_do.bml.error.badusername2", {
                'sitename' => $LJ::SITENAMESHORT,
                'aopts'    => "href='$LJ::SITEROOT/lostinfo.bml'",
            });
        return;
    }

    unless ($up->is_person) {
        push @$errret,
            LJ::Lang::ml("/htdocs/talkpost_do.bml.error.postshared");
        return;
    }

    # if ecphash present, authenticate on that
    if ($form->{'ecphash'}) {
        my $calc_ecp = LJ::Talk::ecphash( int $init->{'itemid'}+0,
                                          $form->{'parenttalkid'},
                                          $up->password );
        if ($form->{'ecphash'} eq $calc_ecp) {
            $init->{'used_ecp'} = 1;
        } else {
            push @$errret,
                LJ::Lang::ml("/htdocs/talkpost_do.bml.error.badpassword2", {
                    'aopts' => "href='$LJ::SITEROOT/lostinfo.bml'",
                });
            return;
        }
    # otherwise authenticate on username/password
    } else {
        my $ok;

        if ($form->{'response'}) {
            $ok = LJ::challenge_check_login( $up, $form->{'chal'},
                                             $form->{'response'} );
        } else {
            $ok = LJ::auth_okay( $up, $form->{'password'},
                                 $form->{'hpassword'} );
        }

        unless ($ok) {
            push @$errret,
                LJ::Lang::ml("/htdocs/talkpost_do.bml.error.badpassword2", {
                    'aopts' => "href='$LJ::SITEROOT/lostinfo.bml'",
                });
            return;
        }
    }

    # if the user chooses to log in, do so
    if ($form->{'do_login'} && ! @$errret) {
        $init->{'didlogin'} = $up->make_login_session($exptype, $ipfixed);
    } else {
        # record their login session anyway
        LJ::Session->record_login($up);
    }

    return $up;
}

1;
