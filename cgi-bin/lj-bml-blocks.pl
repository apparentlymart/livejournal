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

{
    my $dl = "<a href=\"$LJ::SITEROOT/files/%%DATA%%\">HTTP</a>";
    if ($LJ::FTPPREFIX) {
        $dl .= " - <a href=\"$LJ::FTPPREFIX/%%DATA%%\">FTP</a>";
    }
    BML::register_block("DL", "DR", $dl);
}

if ($LJ::UNICODE) {
    BML::register_block("METACTYPE", "S", '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">')
} else {
    BML::register_block("METACTYPE", "S", '<meta http-equiv="Content-Type" content="text/html">')
}


1;
