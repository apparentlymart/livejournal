#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::FotoBilder;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED
                         HTTP_MOVED_PERMANENTLY BAD_REQUEST);

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
    };
    return undef unless $interface->{$cmd};

    return $interface->{$cmd}->(@_);
}

sub handler
{
    my $r = shift;
    my $uri = $r->uri;
    return 404 unless $uri =~ m#^/interface/fotobilder(?:/(\w+))?$#;
    my $cmd = $1;

    return BAD_REQUEST unless $r->method eq "POST";

    $r->content_type("text/plain");
    $r->send_http_header();

    my %POST = $r->content;
    my $res = run_method($cmd, \%POST)
        or return BAD_REQUEST;

    $res->{"fotobilder-interface-version"} = 1;

    $r->print(join("\n", map { "$_: $res->{$_}" } keys %$res));

    return OK;
}

# Is there a current LJ session?
# If so, return info.
sub get_user_info
{
    my $POST = shift;
    BML::reset_cookies();
    $LJ::_XFER_REMOTE_IP = $POST->{'remote_ip'};

    # try to get a $u from the passed uid or user, falling back to the ljsession cookie
    my $u;
    if ($POST->{uid}) {
        $u = LJ::load_userid($POST->{uid});
    } elsif ($POST->{user}) {
        $u = LJ::load_user($POST->{user});
    } else {
        $u = LJ::get_remote();
    }
    return {} unless $u && $u->{'journaltype'} eq 'P';

    my %ret = (
               user            => $u->{user},
               userid          => $u->{userid},
               can_upload      => can_upload($u),
               gallery_enabled => 1, # future toggle
               diskquota       => LJ::get_cap($u, 'disk_quota') << 10,
               totalusage      => LJ::Blob::get_disk_usage($u) >> 10,
               );

    # now optional site-specific info
    if (LJ::are_hooks("fb_rpc_user_info")) {
        my $inf = LJ::run_hook("fb_rpc_user_info", $u);
        while (my ($key, $val) = each %$inf) {
            $ret{$key} = $val;
        }
    }

    return \%ret;
}

# get_user_info above used to be called 'checksession', maintain
# an alias for compatibility
sub checksession { get_user_info(@_); }

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
        my $resp = Digest::MD5::md5_hex($chal . Digest::MD5::md5_hex($u->{'password'}));
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

    my $dbcm = LJ::get_cluster_master($u);
    return {} unless $dbcm;

    my $used = $POST->{'used'} << 10;  # Kb -> bytes
    my $result = $dbcm->do('REPLACE INTO userblob SET ' .
                           'domain=?, length=?, journalid=?, blobid=0',
                           undef, LJ::get_blob_domainid('picpix_quota'),
                           $used, $u->{'userid'});

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

# Does the user have upload access?  (ignoring quota restrictions)
sub can_upload
{
    my $u = shift;
    return LJ::get_cap($u, 'fb_account') ? 1 : 0;
}

1;
