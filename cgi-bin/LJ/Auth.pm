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

    $remote = LJ::want_user($remote) or croak "Invalid remote";
    croak "No URI specified" unless $uri;

    my ($stime, $secret) = LJ::get_secret();
    my $postvars = join('&', map { $postvars{$_} } sort keys %postvars);
    my $remote_session_id = $remote && $remote->session ? $remote->session->id : '';
    my $authstring = sha1_hex(qq {$stime:$secret:$remote->{userid}:$remote_session_id:$uri:$postvars});
    return hmac_sha1_hex($authstring);
}

# Checks an auth token sent by an ajax request
# Arguments: $remote, $uri, %POST variables
# Returns: bool whether or not key is good
sub check_ajax_auth_token {
    my ($class, $remote, $uri, %postvars) = @_;

    $remote = LJ::want_user($remote) or croak "Invalid remote";
    my $authtoken = delete $postvars{auth_token} or return 0;

    return $authtoken eq LJ::Auth->ajax_auth_token($remote, $uri, %postvars);
}

1;
