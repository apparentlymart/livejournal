#!/usr/bin/perl
#

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
use Apache;
use Apache::LiveJournal;
use Apache::CompressClientFixup;
use Apache::BML;
BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlang.pl";
    require "$ENV{'LJHOME'}/cgi-bin/ljpoll.pl";
    require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
    require "$ENV{'LJHOME'}/cgi-bin/htmlcontrols.pl";
    require "$ENV{'LJHOME'}/cgi-bin/imageconf.pl";
    require "$ENV{'LJHOME'}/cgi-bin/propparse.pl";
    require "$ENV{'LJHOME'}/cgi-bin/supportlib.pl";
    require "$ENV{'LJHOME'}/cgi-bin/cleanhtml.pl";
    require "$ENV{'LJHOME'}/cgi-bin/portal.pl";
    require "$ENV{'LJHOME'}/cgi-bin/talklib.pl";
    require "$ENV{'LJHOME'}/cgi-bin/ljtodo.pl";
    require "$ENV{'LJHOME'}/cgi-bin/directorylib.pl";
}

# auto-load some stuff before fork:
Storable::thaw(Storable::freeze({}));

# setup httpd.conf things for the user:
Apache->httpd_conf("DocumentRoot $LJ::HTDOCS")
    if $LJ::HTDOCS;
Apache->httpd_conf("ServerAdmin $LJ::ADMIN_EMAIL")
    if $LJ::ADMIN_EMAIL;

Apache->httpd_conf(qq{

# This interferes with LJ's /~user URI, depending on the module order
<IfModule mod_userdir.c>
  UserDir disabled
</IfModule>

PerlInitHandler +Apache::LiveJournal
PerlFixupHandler +Apache::CompressClientFixup
DirectoryIndex index.html index.bml
});

unless ($LJ::SERVER_TOTALLY_DOWN)
{
    Apache->httpd_conf(qq{
# BML support:
PerlSetVar BMLDomain lj-$LJ::DOMAIN
PerlModule Apache::BML
<Perl>
  Apache::BML::load_config("lj-$LJ::DOMAIN", "$LJ::HOME/cgi-bin/bmlp.cfg");
</Perl>
<Files ~ "\\.bml\$">
  SetHandler perl-script
  PerlHandler Apache::BML
</Files>

# User-friendly error messages
ErrorDocument 404 /404-error.html
ErrorDocument 500 /500-error.html

});
}

# set this before we fork
$LJ::CACHE_CONFIG_MODTIME = (stat("$ENV{'LJHOME'}/cgi-bin/ljconfig.pl"))[9];

1;
