#!/usr/bin/perl
#

my $target = shift;
$target ||= "all";

my $docraw = "$ENV{'LJHOME'}/doc/raw/";
my $htmldir = "$ENV{'LJHOME'}/htdocs/doc/";

mkdir $htmldir, 0755 unless (-d $htmldir);

chdir $htmldir;
system("jade", 
       "-t", "sgml", 
       "-d", "$docraw/ljstyle.dsl", 
       "/usr/lib/sgml/declaration/xml.dcl", "$docraw/book.xml");



