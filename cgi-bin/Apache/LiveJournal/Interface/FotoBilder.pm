#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::FotoBilder;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED
                         HTTP_MOVED_PERMANENTLY BAD_REQUEST);

sub handler
{
    my $r = shift;
    my $uri = $r->uri;
    return 404 unless $uri =~ m#^/interface/fotobilder(?:/(\w+))?$#;
    my $cmd = $1;
    return BAD_REQUEST if $cmd && $r->method ne "POST";

    # Available functions for this interface.
    my $interface = {
        'checksession'  => \&checksession,
        'makechals'     => \&makechals,
        'set_quota'     => \&set_quota,
        'user_exists'   => \&user_exists,
        'get_auth_challenge' => \&get_auth_challenge,
    };

    return BAD_REQUEST unless ref $interface->{$cmd} eq 'CODE';

    $r->content_type("text/plain");
    $r->send_http_header();
    $r->print("fotobilder-interface-version: 1\n");

    my %POST = $r->content;
    return $interface->{$cmd}->($r, %POST) || OK;
}

# Is there a current LJ session?
# If so, return info.
sub checksession
{
    my ($r, %POST) = @_;
    BML::reset_cookies();
    $LJ::_XFER_REMOTE_IP = $POST{'remote_ip'};
    my $remote = LJ::get_remote();
    return OK unless $remote;

    $r->print("user: $remote->{'user'}\n");
    my $u = LJ::load_user($remote->{'user'});
    $r->print("userid: $u->{'userid'}\n");

    $r->print("can_upload: " . (can_upload($u)) . "\n");
    $r->print("gallery_visible: 1\n"); # future toggle
    my $quota      = LJ::get_cap($u, 'disk_quota') << 10;
    my $fbusage    = LJ::Blob::get_disk_usage($u, 'picpix_quota') >> 10;
    my $totalusage = LJ::Blob::get_disk_usage($u) >> 10;

    $r->print("diskquota: $quota\n");
    $r->print("fbusage: $fbusage\n");
    $r->print("totalusage: $totalusage\n");
    return OK;
}

# Pregenerate a list of challenge/responses.
sub makechals
{
    my ($r, %POST) = @_;
    my $count = int($POST{'count'}) || 1;
    if ($count > 50) { $count = 50; }
    my $u = LJ::load_user($POST{'user'});
    return OK unless $u;

    $r->print("count: $count\n");
    for (my $i=1; $i<=$count; $i++) {
        my $chal = LJ::rand_chars(40);
        my $resp = Digest::MD5::md5_hex($chal . Digest::MD5::md5_hex($u->{'password'}));
        $r->print("chal_$i: $chal\nresp_$i: $resp\n");
    }
    return OK;
}

# Does the user exist?
sub user_exists
{
    my ($r, %POST) = @_;
    my $u = LJ::load_user($POST{'user'});
    if ($u) {
        $r->print("exists: 1\n");
        $r->print("can_upload: " . (can_upload($u)) . "\n");
    }
    return OK;
}

# Does the user have upload access?  (ignoring quota restrictions)
sub can_upload
{
    my $u = shift;
    return LJ::get_cap($u, 'fb_account') ? 1 : 0;
}

# Mirror FB quota information over to LiveJournal.
# 'user' - username
# 'used' - FB disk usage in bytes
sub set_quota
{
    my ($r, %POST) = @_;
    my $u = LJ::load_user($POST{'user'});
    return OK unless $u && defined $POST{'used'};

    my $used = $POST{'used'} << 10;  # Kb -> bytes

    my $dbcm = LJ::get_cluster_master($u);
    return OK unless $dbcm;

    my $result = $dbcm->do('REPLACE INTO userblob SET ' .
                           'domain=?, length=?, journalid=?, blobid=0',
                           undef, LJ::get_blob_domainid('picpix_quota'),
                           $used, $u->{'userid'});

    $r->print("status: " . ($result ? 1 : 0) . "\n");
    return OK;
}

sub get_auth_challenge
{
    my ($r, %POST) = @_;
    $r->print("chal: " . LJ::challenge_generate($POST{'goodfor'}) . "\n");
    return OK;
}

1;
