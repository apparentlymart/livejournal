#!/usr/bin/perl

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljviews.pl";

use Compress::Zlib;
use FCGI;
use CGI;

my $REQ_COUNT = 0;
my $REQ_MAX = 500;

while(LJ::start_request() && 
      ++$REQ_COUNT <= $REQ_MAX && FCGI::accept() >= 0) 
{
    my $dbs = LJ::get_dbs();

    my %FORM = ();
    LJ::get_form_data(\%FORM);

    my $ctype = "text/html";
    if ($FORM{'type'} eq "xml") {
	$ctype = "text/xml";
    }
    print "Content-type: $ctype\n";

    my $user = $FORM{'username'} || $FORM{'user'};
    my $styleid = $FORM{'styleid'} + 0;
    my $nooverride = $FORM{'nooverride'} ? 1 : 0;

    my $remote;
    if ($FORM{'checkcookies'}) {
	my $cgi = new CGI;
	my $criterr = 0;
	$remote = LJ::get_remote($dbs, \$criterr, $cgi);
    }

    my $data = (LJ::make_journal($dbs, $user, "", $remote,
				 { "nocache" => $FORM{'nocache'}, 
				   "vhost" => "customview",
				   "nooverride" => $nooverride,
				   "styleid" => $styleid,
			       })
		|| "<b>[$LJ::SITENAME: Bad username, styleid, or style definition]</b>");
    
    if ($FORM{'enc'} eq "js") {
	$data =~ s/\\/\\\\/g;
	$data =~ s/\"/\\\"/g;
	$data =~ s/\n/\\n/g;
	$data =~ s/\r//g;
	$data = "document.write(\"$data\")";
    }

    print "Cache-Control: must-revalidate\n";

    if (0 && $ENV{'HTTP_ACCEPT_ENCODING'} =~ /gzip/) {
	my $gzip = Compress::Zlib::memGzip($data);
	print "Content-Encoding: gzip\n";
	print "Content-length: ", length($gzip), "\n\n";
	print $gzip;
    } else {
	print "Content-length: ", length($data), "\n";
	print "\n";
	print $data;
    }
}
