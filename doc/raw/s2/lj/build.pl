#!/usr/bin/perl
#
use strict;
use Getopt::Long;
my $XSL_VERSION_RECOMMENDED = "1.55.0";
my $opt_clean;
my ($opt_myxsl, $opt_getxsl);
exit 1 unless GetOptions('clean' => \$opt_clean,
                         'myxsl' => \$opt_myxsl,
                         'getxsl' => \$opt_getxsl,
                         );
my $home = $ENV{'LJHOME'};
require "$home/cgi-bin/ljlib.pl";
$ENV{'SGML_CATALOG_FILES'} = $LJ::CATALOG_FILES || "/usr/share/sgml/docbook/dtd/xml/4.1/docbook.cat";
unless (-e $ENV{'SGML_CATALOG_FILES'}) {
    die "Catalog files don't exist.  Either set \$LJ::CATALOG_FILES, install docbook-xml (on Debian), or symlink $ENV{'SGML_CATALOG_FILES'} to XML DocBook 4.1's docbook.cat.";
}
if ($opt_getxsl) {
    chdir "$home/doc/raw/build" or die "Where is build dir?";
    unlink "xsl-docbook.tar.gz";
    my $fetched =  0;
    my $url = "http://www.livejournal.org/misc/xsl-docbook.tar.gz";
    my @fetcher = ([ 'wget', "wget $url", ],
                   [ 'lynx', "lynx -source $url > xsl-docbook.tar.gz", ],
                   [ 'GET', "GET $url > xsl-docbook.tar.gz", ]);
    foreach my $fet (@fetcher) {
        next if $fetched;
        print "Looking for $fet->[0] ...\n";
        next unless `which $fet->[0]`;
        print "RUNNING: $fet->[1]\n";
        system($fet->[1])
            and die "Error running $fet->[0].  Interrupted?\n";
        $fetched = 1;
    }
    unless ($fetched) {
        die "Couldn't find a program to download things from the web.  I looked for:\n\t".
            join(", ", map { $_->[0] } @fetcher) . "\n";
    }
    system("tar", "zxvf", "xsl-docbook.tar.gz")
        and die "Error extracting xsl-doxbook.tar.gz; have GNU tar?\n";
}
my $output_dir = "$home/htdocs/doc/s2";
my $docraw_dir = "$home/doc/raw";
my $XSL = "$docraw_dir/build/xsl-docbook";
open (F, "$XSL/VERSION");
my $XSL_VERSION;
{ 
    local $/ = undef; my $file = <F>; 
    $XSL_VERSION = $1 if $file =~ /VERSION.+\>(.+?)\</;
}
close F;
my $download;
if ($XSL_VERSION && $XSL_VERSION ne $XSL_VERSION_RECOMMENDED && ! $opt_myxsl) {
    print "\nUntested DocBook XSL found at $XSL.\n";
    print "   Your version: $XSL_VERSION.\n";
    print "    Recommended: $XSL_VERSION_RECOMMENDED.\n\n";
    print "Options at this point.  Re-run with:\n";
    print "    --myxsl    to proceed with yours, or\n";
    print "    --getxsl   to install recommended XSL\n\n";
    exit 1;
}
if (! $XSL_VERSION) {
    print "\nDocBook XSL not found at $XSL.\n\nEither symlink that dir to the right ";
    print "place (preferrably at version $XSL_VERSION_RECOMMENDED),\nor re-run with --getxsl ";
    print "for me to do it for you.\n\n";
    exit 1;
}

open(AUTOGEN, ">$docraw_dir/s2/lj/autogen-entities.xml") || die "Can't open autogen-entities.xml\n";
print AUTOGEN "<!ENTITY siteroot \"$LJ::SITEROOT\">\n";
close(AUTOGEN);

my $cssparam;
if (-e "$docraw_dir/build/style.css") {
    $cssparam = "--stringparam html.stylesheet style.css";
    system("cp", "$docraw_dir/build/style.css", "$output_dir")
        and die "Error copying stylesheet.\n";
}

mkdir $output_dir, 0755 unless -d $output_dir;
chdir $output_dir or die "Couldn't chdir to $output_dir\n";
system("xsltproc --nonet --catalogs $cssparam ".
       "$docraw_dir/build/ljdocs2html.xsl $docraw_dir/s2/lj/index.xml")
    and die "Error generating HTML.\n";
