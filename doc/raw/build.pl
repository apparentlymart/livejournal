#!/usr/bin/perl
#

my $target = shift;
$target ||= "all";

my $docraw = "$ENV{'LJHOME'}/doc/raw/";
my $htmldir = "$ENV{'LJHOME'}/htdocs/doc/";

chdir "$docraw/int/db" or die;
print "Make dbschema.gen\n";
system("./dbschema.pl > dbschema.gen");

print "Make schemaref.gen\n";
system("java -cp /usr/share/java/saxon.jar com.icl.saxon.StyleSheet dbschema.gen db2ref.xsl > schemaref.gen");

print "Make HTML.\n";
mkdir $htmldir, 0755 unless (-d $htmldir);
chdir $htmldir;
system("jade", 
       "-t", "sgml", 
       "-d", "$docraw/ljstyle.dsl", 
       "/usr/lib/sgml/declaration/xml.dcl", "$docraw/book.xml");

