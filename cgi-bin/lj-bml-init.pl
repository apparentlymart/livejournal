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

BML::register_hook("startup", sub { LJ::start_request() });

if ($LJ::UNICODE) {
    BML::set_default_content_type("text/html; charset=utf-8");
}

# pre-load common libraries so we don't have to load them in BML files (slow)
package BMLCodeBlock;
use LJ::TextMessage;
use LJ::TagGenerator ':html4';
use Digest::MD5 qw(md5_hex);
use MIME::Words qw(encode_mimewords);

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
require 'directorylib.pl';

# register BML multi-language hook
BML::register_ml_getter(sub {
    my ($lang, $code) = @_;
    # FIXME: bare-minimum implementation.  add memoization later.
    my $dbr = LJ::get_dbh("slave", "master");
    my $langid = $dbr->selectrow_array("SELECT lnid FROM ml_langs WHERE lncode=" . $dbr->quote($lang));
    my $text = $dbr->selectrow_array("SELECT t.text FROM ml_text t, ml_latest l, ml_items i WHERE t.dmid=1 ".
                                     "AND t.txtid=l.txtid AND l.dmid=1 AND l.lnid=$langid AND l.itid=i.itid ".
                                     "AND i.dmid=1 AND i.itcode=" . $dbr->quote($code));
    return $text;
});

1;
