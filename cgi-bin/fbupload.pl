#!/usr/bin/perl

package LJ::FBUpload;
use strict;

require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use MIME::Words ();
use IO::Handle;
use LWP::UserAgent;
use URI::Escape;
use Digest::MD5 ();
use File::Basename ();

*hash = \&Digest::MD5::md5_hex;

sub make_auth
{
    my ($chal, $password) = @_;
    return unless $chal && $password;
    return "crp:$chal:" . hash($chal . hash($password));
}

sub get_challenge
{
    my ($u, $ua, $err) = @_;
    return unless $u && $ua;

    my $req = HTTP::Request->new(PUT => "$LJ::FB_SITEROOT/interface/upload");
    $req->push_header("X-FB-Username" => $u->{'user'});
    $req->push_header("X-FB-MakeChallenge" => 1);

    my $res = $$ua->request($req);
    if ($res->is_success()) {
        return scalar $res->header("X-FB-NewChallenge");
    } else {
        $$err = $res->content();
        return;
    }
}

# on success, returns title/url pair for uploaded picture
# on failure, returns http code or undef,
#             sets $rv reference with errorstring.
# opts: { path    => path to image on disk
#         rawdata => optional image data scalar ref
#         imgsec  => bitmask for image security
#         galname => gallery to upload image to }
sub do_upload 
{
    my ($u, $rv, $opts) = @_;
    unless ($u && $opts->{'path'}) {
        $$rv = "Invalid parameters to do_upload()";
        return;
    }

    my $ua = LWP::UserAgent->new;
    $ua->agent("LiveJournal_FBUpload/0.1");

    my $err;
    my $chal = get_challenge($u, \$ua, \$err);
    unless ($chal) {
        $$rv = "Error getting challenge from FB server: $err";
        return;
    }

    my $rawdata = $opts->{'rawdata'};
    unless ($rawdata) {
        # no rawdata was passed, so slurp it in ourselves
        unless (open (F, $opts->{'path'})) {
            $$rv = "Couldn't read image file: $!\n";
            return;
        }
        binmode(F);
        my $data;
        { local $/ = undef; $data = <F>; }
        $rawdata = \$data;
        close F;
    }

    my $basename = File::Basename::basename($opts->{'path'});
    my $magic = substr($$rawdata, 0, 10);
    $magic =~ s/(.)/lc sprintf("%02x",ord($1))/egs;
    $opts->{'imgsec'} = 255 unless defined $opts->{'imgsec'};
    $opts->{'galname'} ||= 'LJ_emailpost';

    my $req = HTTP::Request->new(PUT => "$LJ::FB_SITEROOT/interface/upload");
    my %headers = (
            'Content-Length'          => length($$rawdata),
            'X-FB-Meta-Filename'      => uri_escape($basename),
            'X-FB-Magic'              => $magic,
            'X-FB-MD5'                => hash($$rawdata),
            'X-FB-Username'           => $u->{'user'},
            'X-FB-Auth'               => make_auth($chal, $u->{'password'}),
            'X-FB-Security'           => $opts->{'imgsec'},
            'X-FB-Gallery'            =>
                    'name=' . (uri_escape($opts->{'galname'})) .  '&galsec=255',
            );

    foreach my $hdr (keys %headers) {
        $req->push_header($hdr, $headers{$hdr});
    }

    $req->content($$rawdata);
    my $res = $ua->request($req);

    my $res_code = $1 if $res->status_line =~ /^(\d+)/;
    if ($res->is_success) {
        my $url = $1 if $res->content() =~ /URL: (\S+)/;
        return wantarray ? ($basename, $url) : $url;
    } else {
        $$rv = "Error uploading pict: " . $res->content();
        return $res_code;
    }

}

1;
