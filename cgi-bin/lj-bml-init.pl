#!/usr/bin/perl
#
    
require "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";

foreach (@LJ::LANGS) {
    BML::register_isocode(substr($_, 0, 2), $_);
    BML::register_language($_);
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
    BML::register_block("DL", "DR", $dl);
}

# set default path/domain for cookies
BML::set_config("/", "CookieDomain" => $LJ::COOKIE_DOMAIN);
BML::set_config("/", "CookiePath"   => $LJ::COOKIE_PATH);

BML::register_hook("startup", sub {
    my $r = Apache->request;
    my $uri = "bml" . $r->uri;
    unless ($uri =~ s/\.bml$//) {
        $uri .= ".index";
    }
    $uri =~ s!/!.!g;
    $r->notes("codepath" => $uri);
});

BML::register_hook("codeerror", sub {
    my $msg = shift;
    if ($msg =~ /Can\'t call method.*on an undefined value/) {
        return "Sorry, database temporarily unavailable.";
    }
    return "<b>[Error: $msg]</b>";
}) unless $LJ::IS_DEV_SERVER;

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
use Storable;
use Image::Size ();
Image::Size::imgsize("GIF89a"); 
Image::Size::imgsize("\x89PNG\x0d\x0a\x1a\x0a");
Image::Size::imgsize("\xFF\xD8");  # JPEG

require "$ENV{'LJHOME'}/cgi-bin/imageconf.pl";
require "$ENV{'LJHOME'}/cgi-bin/propparse.pl";
require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljprotocol.pl";
require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
require "$ENV{'LJHOME'}/cgi-bin/emailcheck.pl";
require "$ENV{'LJHOME'}/cgi-bin/portal.pl";
require "$ENV{'LJHOME'}/cgi-bin/talklib.pl";
require "$ENV{'LJHOME'}/cgi-bin/ljtodo.pl";
require "$ENV{'LJHOME'}/cgi-bin/directorylib.pl";

# register BML multi-language hook
BML::register_ml_getter(\&LJ::Lang::get_text);

# open a db connection to force DBI to autoload its driver code before
# apache forks
{
    my ($dsn, $user, $pass) = split(/\|/, $LJ::DBIRole->make_dbh_fdsn($LJ::DBINFO{'master'}));
    my $dbh = DBI->connect($dsn, $user, $pass);
    my $num = $dbh->selectrow_array("SELECT COUNT(*) FROM stats");
    $dbh->disconnect;
}

1;
