#!/usr/bin/perl
#

require 'ljconfig.pl';

BML::register_block("DOMAIN", "S", $LJ::DOMAIN);
BML::register_block("IMGPREFIX", "S", $LJ::IMGPREFIX);
BML::register_block("SITEROOT", "S", $LJ::SITEROOT);
BML::register_block("SITENAME", "S", $LJ::SITENAME);
BML::register_block("ADMIN_EMAIL", "S", $LJ::ADMIN_EMAIL);
BML::register_block("SUPPORT_EMAIL", "S", $LJ::SUPPORT_EMAIL);

{
    my $dl = "<a href=\"$LJ::SITEROOT/files/%%DATA%%\">HTTP</a>";
    if ($LJ::FTPPREFIX) {
	$dl .= " - <a href=\"$LJ::FTPPREFIX/%%DATA%%\">FTP</a>";
    }
    BML::register_block("DL", "DS", $dl);
}

# pre-load common libraries so we don't have to load them in BML files (slow)
package BMLCodeBlock;
use LJ::TextMessage;
use LJ::TagGenerator ':html4';
use Digest::MD5 qw(md5_hex);
require 'imageconf.pl';
require 'propparse.pl';
require 'supportlib.pl';
require 'ljlib.pl';
require 'ljprotocol.pl';
require 'cleanhtml.pl';
require 'emailcheck.pl';
require 'portal.pl';
require 'talklib.pl';
require 'topiclib.pl';
require 'ljtodo.pl';

1;
