#!/usr/bin/perl

package LJ::FBUpload;
use strict;

require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
use MIME::Words ();
use XML::Simple;
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

    my $req = HTTP::Request->new(GET => "$LJ::FB_SITEROOT/interface/simple");
    $req->push_header("X-FB-Mode" => "GetChallenge");
    $req->push_header("X-FB-User" => $u->{'user'});
    
    my $res = $$ua->request($req);
    if ($res->is_success()) {

        my $xmlres = XML::Simple::XMLin($res->content);
        my $methres = $xmlres->{GetChallengeResponse};
        return $methres->{Challenge};

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
    $ua->agent("LiveJournal_FBUpload/0.2");

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
    my $length = length $$rawdata;
    $opts->{'imgsec'} = 255 unless defined $opts->{'imgsec'};
    $opts->{'galname'} ||= 'LJ_emailpost';

    my $req = HTTP::Request->new(PUT => "$LJ::FB_SITEROOT/interface/simple");
    my %headers = (
        'X-FB-Mode'                    => 'UploadPic',
        'X-FB-UploadPic.ImageLength'   => $length,
        'Content-Length'               => $length,
        'X-FB-UploadPic.Meta.Filename' => uri_escape($basename),
        'X-FB-UploadPic.MD5'           => hash($$rawdata),
        'X-FB-User'                    => $u->{'user'},
        'X-FB-Auth'                    => make_auth( $chal, $u->{'password'} ),
        ':X-FB-UploadPic.Gallery._size'=> 1,
        'X-FB-UploadPic.PicSec'        => $opts->{'imgsec'} || 255,
        'X-FB-UploadPic.Gallery.0.GalName' => uri_escape( $opts->{'galname'} ),
        'X-FB-UploadPic.Gallery.0.GalSec'  => 255
    );

    $req->push_header($_, $headers{$_}) foreach keys %headers;

    $req->content($$rawdata);
    my $res = $ua->request($req);

    my $res_code = $1 if $res->status_line =~ /^(\d+)/;
    if ($res->is_success) {
        my $xmlres = XML::Simple::XMLin($res->content);
        my $methres = $xmlres->{UploadPicResponse};

        my $err_str = $xmlres->{Error}->{content} ||
                      $methres->{Error}->{content};
        if ($err_str) {
            $$rv = "Protocol error during upload: $err_str";
            return $xmlres->{Error}->{code} ||
                   $methres->{Error}->{code};
        }

        # good at this point
        my $url = $methres->{URL};
        return wantarray ? ($basename, $url) : $url;
    } else {
        $$rv = "HTTP error uploading pict: " . $res->content();
        return $res_code;
    }

}

1;
