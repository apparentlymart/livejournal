#!/usr/bin/perl
#

use Digest::MD5;
use HTTP::Date;

my $ret = "";

$ret .= "<html><head><title>dump output</title></head><body>\n";
$ret .= "Host: " . `hostname`;
$ret .= "<h2>Environment variables</h2><pre>\n";
foreach $key (sort(keys(%ENV))){
    my $val = $ENV{$key};
    if ($key eq "HTTP_COOKIE") {
	$val =~ s/ljhpass=.+?;/ljhpass=XXXX;/g;
    }
    $ret .= "<B>$key</B>" . " "x(23-length($key)) . "= $val\n";
}

$ret .= "</pre>\n";

if ($ENV{'REQUEST_METHOD'} eq "GET") {
    $in = $ENV{'QUERY_STRING'};
    $ret .= "<h2>REQUEST_METHOD was GET</h2><pre>\n";
    $ret .= "Stdin= [$in]\n";
    $ret .= "</pre>\n";
} elsif ($ENV{'REQUEST_METHOD'} eq "POST") {
    $ret .= "<h2>REQUEST_METHOD was POST</h2><pre>\n";
    $ret .= "Stdin= [";
    while ($bytes = read(STDIN, $data, 1024))
    {
	$ret .= $data;
    }
    $ret .= "]\n";

    $ret .= "</pre>\n";
} 
$ret .= "</body></html>\n";

print "ETag: ", Digest::MD5::md5_hex($ret), "\n";
print "Last-Modified: ", HTTP::Date::time2str(time()), "\n";
print "Cache-Control: private, must-revalidate\n";
print "Content-length: ", length($ret), "\n";
print "Content-Type: text/html\n\n";

print $ret;

exit 0;

