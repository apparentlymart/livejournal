#!/usr/bin/perl
#
    
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

foreach (@LJ::LANGS) {
    BML::register_language(substr($_, 0, 2), $_);
}

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

# set default path/domain for cookies
BML::set_config("/", "CookieDomain" => $LJ::COOKIE_DOMAIN);
BML::set_config("/", "CookiePath"   => $LJ::COOKIE_PATH);

BML::register_hook("startup", sub {
    LJ::start_request();
    eval {
        Apache->request->notes("ljuser" => $BML::COOKIE{'ljuser'});
    };
});

if ($LJ::UNICODE) {
    BML::set_default_content_type("text/html; charset=utf-8");
}

# pre-load common libraries so we don't have to load them in BML files (slow)
package BMLCodeBlock;
use LJ::SpellCheck;
use LJ::TextMessage;
use LJ::TagGenerator ':html4';
use Digest::MD5 qw(md5_hex); # TODO: don't import
use MIME::Words;
use LWP::UserAgent ();
use Image::Size ();

require "$ENV{'LJHOME'}/cgi-bin/imageconf.pl";
require "$ENV{'LJHOME'}/cgi-bin/propparse.pl";
require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
require "$ENV{'LJHOME'}/cgi-bin/emailcheck.pl";
require "$ENV{'LJHOME'}/cgi-bin/portal.pl";
require "$ENV{'LJHOME'}/cgi-bin/talklib.pl";
require "$ENV{'LJHOME'}/cgi-bin/topiclib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljtodo.pl";
require "$ENV{'LJHOME'}/cgi-bin/directorylib.pl";

# register BML multi-language hook
BML::register_ml_getter(\&LJ::Lang::get_text_bml);

# open a db connection to force DBI to autoload its driver code before
# apache forks
{
    my $dbh = DBI->connect(LJ::_make_dbh_fdsn($LJ::DBINFO{'master'}));
    my $num = $dbh->selectrow_array("SELECT COUNT(*) FROM stats");
    $dbh->disconnect;
}

1;
