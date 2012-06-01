# This is the LiveJournal Authentication module.
# It contains useful authentication methods.

package LJ::Auth;
use strict;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use Digest::SHA1 qw(sha1_hex);
use Carp qw (croak);

# Generate an auth token for AJAX requests to use.
# Arguments: ($remote, $action, %postvars)
#   $remote: remote user object
#   $uri: what uri this is for
#   %postvars: the expected post variables
# Returns: Auth token good for the current hour
sub ajax_auth_token {
    my ($class, $remote, $uri, %postvars) = @_;

    $remote = LJ::want_user($remote) || LJ::get_remote();

    croak "No URI specified" unless $uri;

    my ($stime, $secret) = LJ::get_secret();
    my $postvars = join('&', map { $postvars{$_} } sort keys %postvars);
    my $remote_session_id = $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;
    my $remote_userid = $remote ? $remote->id : 0;

    my $chalbare = qq {ajax:$stime:$remote_userid:$remote_session_id:$uri:$postvars};
    my $chalsig = sha1_hex($chalbare, $secret);
    return qq{$chalbare:$chalsig};
}

# Checks an auth token sent by an ajax request
# Arguments: $remote, $uri, %POST variables
# Returns: bool whether or not key is good
sub check_ajax_auth_token {
    my ($class, $remote, $uri, %postvars) = @_;

    $remote = LJ::want_user($remote) || LJ::get_remote();

    # get auth token out of post vars
    my $auth_token = delete $postvars{auth_token} or return 0;

    # recompute post vars
    my $postvars = join('&', map { $postvars{$_} } sort keys %postvars);

    # get vars out of token string
    my ($c_ver, $stime, $remoteid, $sessid, $chal_uri, $chal_postvars, $chalsig) = split(':', $auth_token);

    # get secret based on $stime
    my $secret = LJ::get_secret($stime);

    # no time?
    return 0 unless $stime && $secret;

    # right version?
    return 0 unless $c_ver eq 'ajax';

    # in logged-out case $remoteid is 0 and $sessid is uniq_cookie
    my $req_remoteid = $remoteid > 0 ? $remote->id : 0;
    my $req_sessid   = $remoteid > 0 ? $remote->session->id : LJ::UniqCookie->current_uniq;


    # do signitures match?
    my $chalbare = qq {$c_ver:$stime:$remoteid:$sessid:$chal_uri:$chal_postvars};
    my $realsig = sha1_hex($chalbare, $secret);
    return 0 unless $realsig eq $chalsig;

    return 0 unless 
        $remoteid == $req_remoteid && # remote id matches or logged-out 0=0
        $sessid == $req_sessid &&     # remote sessid or logged-out uniq cookie match
        $uri eq $chal_uri &&          # uri matches
        $postvars eq $chal_postvars;  # post vars to uri

    return 1;
}

# this is similar to the above methods but doesn't require a session or remote
sub sessionless_auth_token {
    my ($class, $uri, %reqvars) = @_;

    croak "No URI specified" unless $uri;

    my ($stime, $secret) = LJ::get_secret();
    my $reqvars = join('&', map { $reqvars{$_} } sort keys %reqvars);

    my $chalbare = qq {sessionless:$stime:$uri:$reqvars};
    my $chalsig = sha1_hex($chalbare, $secret);
    return qq{$chalbare:$chalsig};
}

sub check_sessionless_auth_token {
    my ($class, $uri, %reqvars) = @_;

    # get auth token out of post vars
    my $auth_token = delete $reqvars{auth_token} or return 0;

    # recompute post vars
    my $reqvars = join('&', map { $reqvars{$_} } sort keys %reqvars);

    # get vars out of token string
    my ($c_ver, $stime, $chal_uri, $chal_reqvars, $chalsig) = split(':', $auth_token);

    # get secret based on $stime
    my $secret = LJ::get_secret($stime);

    # no time?
    return 0 unless $stime && $secret;

    # right version?
    return 0 unless $c_ver eq 'sessionless';

    # do signitures match?
    my $chalbare = qq {$c_ver:$stime:$chal_uri:$chal_reqvars};
    my $realsig = sha1_hex($chalbare, $secret);
    return 0 unless $realsig eq $chalsig;

    # do other vars match?
    return 0 unless $uri eq $chal_uri && $reqvars eq $chal_reqvars;

    return 1;
}

sub login {
    my ($class, $params, $errors) = @_;
    $errors = [] unless $errors && ref($errors) eq 'ARRAY';
    my $res;

    # ! after username overrides expire to never
    # < after username overrides ipfixed to yes
    if ($params->{'user'} =~ s/[!<]{1,2}$//) {
        $params->{'expire'} = 'never' if index($&, "!") >= 0;
        $params->{'bindip'} = 'yes' if index($&, "<") >= 0;
    }

    my $user = LJ::canonical_username($params->{'user'});
    my $password = $params->{'password'};

    my $remote = LJ::get_remote();
    my $cursess = $remote ? $remote->session : undef;
    
    if ($remote) {
        if($remote->readonly) {
            return ($res, error('database_readonly', $errors));
        }
        
        unless ($remote->tosagree_verify) {
            return ($res, error('tos_required', $errors));
        }
                
        unless ( LJ::check_form_auth( {lj_form_auth => $params->{lj_form_auth}} ) ) {
            return ($res, error('authorization_failed', $errors));
        }

        my $bindip;
        $bindip = BML::get_remote_ip()
            if $params->{'bindip'} eq "yes";
        
        $cursess->set_ipfixed($bindip) or die "failed to set ipfixed";
        $cursess->set_exptype($params->{expire} eq 'never' ? 'long' : 'short') or die "failed to set exptype";
        $cursess->update_master_cookie;
        
        return {
            remote      => $remote,
            session     => $cursess,
            do_change   => 1,
        }, $errors;
    }
    my $u = LJ::load_user($user);

    if (! $u) {
        return ($res, error('unknown_user', $errors));
    } else {
        return ($res, error('purged_user', $errors))  if $u->is_expunged;
        return ($res, error('community_disabled_login' , $errors))
            if $u->{'journaltype'} eq 'C' && $LJ::DISABLED{'community-logins'};
    }

    if (LJ::get_cap($u, "readonly")) {
        return ($res, error('database_readonly', $errors));
    }
    
    my ($banned, $ok);
    $banned = $ok = 0;
    my $chal_opts = {};

    if ($params->{response}) {
        $ok = LJ::challenge_check_login($u, $params->{chal}, $params->{response}, \$banned, $chal_opts);
    } else {  # js disabled, fallback to plaintext
        if($params->{md5}) {
            $ok = LJ::auth_okay($u, undef, $password, undef, \$banned);
        } else {
            $ok = LJ::auth_okay($u, $password, undef, undef, \$banned);
        }
    }

    return ($res, error('banned_ip', $errors)) if $banned;

    if ($u && ! $ok) {
        if ($chal_opts->{'expired'}) {
            return ($res, error('expired_challenge', $errors));
        } else {
            return ($res, error('bad_password', $errors));
        }
    }
        
    return ($res, error('account_locked', $errors)) if $u->{statusvis} eq 'L';

    LJ::load_user_props($u, "browselang", "schemepref", "legal_tosagree");

    unless ($u->tosagree_verify) {
        if ($params->{agree_tos}) {
            my $err = "";
            unless ($u->tosagree_set(\$err)) {
                # failed to save userprop, why?
                return ($res, error('fail_tosagree_set', $errors));
            }
            # else, successfully set... log them in
        } else {
            # didn't check agreement checkbox
            return ($res, error('tos_required', $errors));
        }
    }
    
    my $exptype = ($params->{'expire'} eq "never" || $params->{'remember_me'}) ? "long" : "short";
    my $bindip  = ($params->{'bindip'} eq "yes") ? BML::get_remote_ip() : "";
    
    $u->make_login_session($exptype, $bindip);
    LJ::run_hooks('user_login', $u);
    $cursess = $u->session;

    LJ::set_remote($u);
    
    return {
        remote   => $u,
        session  => $cursess,
        do_login => 1,
    }, $errors;
}

sub error {
    my ($err_code, $ref) = @_;

    if(ref $ref eq 'ARRAY') {
        push @$ref, $err_code;
    } elsif(ref $ref eq 'HASH') {
        $ref->{$err_code} = 1;
    } elsif (ref $ref eq 'SCALAR') {
        $$ref = $err_code;
    }

    return $ref;
}

1;
