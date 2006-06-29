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

    $remote = LJ::want_user($remote) || LJ::get_remote()
        or croak "Invalid remote";

    croak "No URI specified" unless $uri;

    my ($stime, $secret) = LJ::get_secret();
    my $postvars = join('&', map { $postvars{$_} } sort keys %postvars);
    my $remote_session_id = $remote && $remote->session ? $remote->session->id : '';

    my $chalbare = qq {ajax:$stime:$remote->{userid}:$remote_session_id:$uri:$postvars};
    my $chalsig = sha1_hex($chalbare, $secret);
    return qq{$chalbare:$chalsig};
}

# Checks an auth token sent by an ajax request
# Arguments: $remote, $uri, %POST variables
# Returns: bool whether or not key is good
sub check_ajax_auth_token {
    my ($class, $remote, $uri, %postvars) = @_;

    $remote = LJ::want_user($remote) || LJ::get_remote()
        or croak "Invalid remote";

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

    # do signitures match?
    my $chalbare = qq {$c_ver:$stime:$remoteid:$sessid:$chal_uri:$chal_postvars};
    my $realsig = sha1_hex($chalbare, $secret);
    return 0 unless $realsig eq $chalsig;

    # do other vars match?
    return 0 unless $remoteid == $remote->{userid} &&
        $remote && $remote->session && $sessid == $remote->session->id &&
        $uri eq $chal_uri && $postvars eq $chal_postvars;

    return 1;
}

1;
