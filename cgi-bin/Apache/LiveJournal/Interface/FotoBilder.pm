#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::FotoBilder;

use strict;

use LJ::FBInterface;

sub run_method
{
    my $cmd = shift;

    # Available functions for this interface.
    my $interface = {
        'checksession'       => \&checksession,
        'get_user_info'      => \&get_user_info,
        'makechals'          => \&makechals,
        'set_quota'          => \&set_quota,
        'user_exists'        => \&user_exists,
        'get_auth_challenge' => \&get_auth_challenge,
        'get_groups'         => \&get_groups,
    };
    return undef unless $interface->{$cmd};

    return $interface->{$cmd}->(@_);
}

sub handler
{
    my $uri = LJ::Request->uri;
    return LJ::Request::NOT_FOUND unless $uri =~ m#^/interface/fotobilder(?:/(\w+))?$#;
    my $cmd = $1;

    return LJ::Request::BAD_REQUEST unless LJ::Request->method eq "POST";

    LJ::Request->content_type("text/plain");
    LJ::Request->send_http_header();

    my %POST = LJ::Request->post_params;
    my $res = run_method($cmd, \%POST)
        or return LJ::Request::BAD_REQUEST;

    $res->{"fotobilder-interface-version"} = 1;

    LJ::Request->print(join("", map { "$_: $res->{$_}\n" } keys %$res));

    return LJ::Request::OK;
}

# Is there a current LJ session?
# If so, return info.
sub get_user_info
{
    my $POST = shift;
    LJ::Request->start_request();

    $LJ::_XFER_REMOTE_IP = $POST->{'remote_ip'};

    return LJ::FBInterface->get_user_info($POST);
}

# get_user_info above used to be called 'checksession', maintain
# an alias for compatibility
sub checksession { get_user_info(@_); }

sub get_groups {
    my $POST = shift;
    my $u = LJ::load_user($POST->{user});
    return {} unless $u;

    my %ret = ();
    LJ::fill_groups_xmlrpc($u, \%ret);
    return \%ret;
}

# Pregenerate a list of challenge/responses.
sub makechals
{
    my $POST = shift;
    my $count = int($POST->{'count'}) || 1;
    if ($count > 50) { $count = 50; }
    my $u = LJ::load_user($POST->{'user'});
    return {} unless $u;

    my %ret = ( count => $count );

    for (my $i=1; $i<=$count; $i++) {
        my $chal = LJ::rand_chars(40);
        my $resp = Digest::MD5::md5_hex($chal . Digest::MD5::md5_hex($u->password));
        $ret{"chal_$i"} = $chal;
        $ret{"resp_$i"} = $resp;
    }

    return \%ret;
}

# Does the user exist?
sub user_exists
{
    my $POST = shift;
    my $u = LJ::load_user($POST->{'user'});
    return {} unless $u;

    return {
        exists => 1,
        can_upload => can_upload($u),
    };
}

# Mirror FB quota information over to LiveJournal.
# 'user' - username
# 'used' - FB disk usage in bytes
sub set_quota
{
    my $POST = shift;
    my $u = LJ::load_userid($POST->{'uid'});
    return {} unless $u && defined $POST->{'used'};

    return {} unless $u->writer;

    my $used = $POST->{'used'} * (1 << 10);  # Kb -> bytes
    my $result = $u->do('REPLACE INTO userblob SET ' .
                        'domain=?, length=?, journalid=?, blobid=0',
                        undef, LJ::get_blob_domainid('fotobilder'),
                        $used, $u->{'userid'});

    $u->set_prop( 'fb_num_pubpics' => $POST->{'pub_pics'} );

    return {
        status => ($result ? 1 : 0),
    };
}

sub get_auth_challenge
{
    my $POST = shift;

    return {
        chal => LJ::challenge_generate($POST->{goodfor}+0),
    };
}

#########################################################################
# non-interface helper functions
#

# Does the user have upload access?
sub can_upload
{
    my $u = shift;

    return LJ::FBInterface->can_upload($u);
}

1;
