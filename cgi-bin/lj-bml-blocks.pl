#!/usr/bin/perl
#
    
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

BML::register_block("DOMAIN", "S", $LJ::DOMAIN);
BML::register_block("IMGPREFIX", "S", $LJ::IMGPREFIX);
BML::register_block("STATPREFIX", "S", $LJ::STATPREFIX);
BML::register_block("SITEROOT", "S", $LJ::SITEROOT);
BML::register_block("SITENAME", "S", $LJ::SITENAME);
BML::register_block("ADMIN_EMAIL", "S", $LJ::ADMIN_EMAIL);
BML::register_block("SUPPORT_EMAIL", "S", $LJ::SUPPORT_EMAIL);
BML::register_block("CHALRESPJS", "", $LJ::COMMON_CODE{'chalresp_js'});

{
    my $dl = "<a href=\"$LJ::SITEROOT/files/%%DATA%%\">HTTP</a>";
    BML::register_block("DL", "DR", $dl);
}

if ($LJ::UNICODE) {
    BML::register_block("METACTYPE", "S", '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">')
} else {
    BML::register_block("METACTYPE", "S", '<meta http-equiv="Content-Type" content="text/html">')
}


1;
