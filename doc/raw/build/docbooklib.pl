#!/usr/bin/perl
#

 use strict;

 my %special = (
     'logprops' => '<xref linkend="ljp.csp.proplist" />',
     'ljhome' => '<envar><link linkend="lj.install.ljhome">\$LJHOME</link></envar>',
     'helpurls' => '<xref linkend="lj.install.ljconfig.helpurls" />',
     'disabled' => '<xref linkend="lj.install.ljconfig.disabled" />',
 );

 sub cleanse
 {
     my $text = shift;
     $$text =~ s/&(?!(?:[a-zA-Z0-9]+|#\d+);)/&amp;/g;
     $$text =~ s/<b>(.+?)<\/b>/<emphasis role='bold'>$1<\/emphasis>/ig;
     $$text =~ s/<tt>(.+?)<\/tt>/<literal>$1<\/literal>/ig;
     $$text =~ s/<i>(.+?)<\/i>/<replaceable type='parameter'>$1<\/replaceable>/ig;
     $$text =~ s/<u>(.+?)<\/u>/<emphasis>$1<\/emphasis>/ig;
     xlinkify($text);
 }
 
 sub canonize
 {
     my $type = lc(shift);
     my $name = shift;
     my $function = shift;
     my $string = lc($name);
     if ($type eq "func") {
         $string =~ s/::/./g;
         my $format = "ljp.api.$string";
         $string = $function eq "link" ? "<link linkend=\"$format\">$name</link>" : $format;
     } elsif($type eq "dbtable") {
         $string = "<link linkend=\"ljp.dbschema.$string\">$name</link>";
     } elsif($type eq "special") {
         $string = %special->{$string};
     } elsif($type eq "ljconfig") {
         $string = "<xref linkend=\"ljconfig.$string\" />";
     }
 }

 sub xlinkify
 {
     my $a = shift;
     $$a =~ s/\[(\S+?)\[(\S+?)\]\]/canonize($1, $2, "link")/ge;
 }
