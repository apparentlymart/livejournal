#!/usr/bin/perl
#

package Apache::LiveJournal::Interface::FotoBilder;

use strict;
use Apache::Constants qw(:common REDIRECT HTTP_NOT_MODIFIED HTTP_MOVED_PERMANENTLY);

sub handler
{
    my $r = shift;
    my $uri = $r->uri;
    return 404 unless $uri =~ m!^/interface/fotobilder(?:/(\w+))?$!;
    my $cmd = $1;
    return 400 if $cmd && $r->method ne "POST";

    my %POST = $r->content;
    $r->content_type("text/plain");
    $r->send_http_header();

    $r->print("fotobilder-interface-version: 1\n");

    if ($cmd eq "checksession") {
        BML::reset_cookies();
        $LJ::_XFER_REMOTE_IP = $POST{'remote_ip'};
        my $remote = LJ::get_remote();
        if ($remote) {
            $r->print("user: $remote->{'user'}\n");
        }
        return OK;
    }

    if ($cmd eq "makechals") {
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


    return OK;
}

1;
