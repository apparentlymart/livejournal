#!/usr/bin/perl
#

 use strict;

 unless (-d $ENV{'LJHOME'}) { die "\$LJHOME not set.\n"; }

 require "$ENV{'LJHOME'}/doc/raw/build/docbooklib.pl";
 require "$ENV{'LJHOME'}/cgi-bin/propparse.pl";

 my @vars;
 LJ::load_objects_from_file("$ENV{'LJHOME'}/htdocs/protocol.dat", \@vars);
 
 foreach my $mode (sort { $a->{'name'} cmp $b->{'name'} } @vars) 
 {
     my $name = $mode->{'name'};
     my $des = $mode->{'props'}->{'des'};
     cleanse(\$des);

     unshift (@{$mode->{'props'}->{'request'}}, 
              { 'name' => "mode", 'props' => { 'des' => "The protocol request mode: <literal>$name</literal>", } },
              { 'name' => "user", 'props' => { 'des' => "Username.  Leading and trailing whitespace is ignored, as is case.", } },
              { 'name' => "password", 'props' => { 'des' => "Password in plain-text.  Either this needs to be sent, or <literal>hpassword</literal>.", } },
              { 'name' => "hpassword", 'props' => { 'des' => "Alternative to plain-text <literal>password</literal>.  Password as an MD5 hex digest.  Not perfectly secure, but defeats the most simple of network sniffers.", } },
              { 'name' => "ver", 'props' => { 'des' => "Protocol version supported by the client; assumed to be 0 if not specified.  See <xref linkend='ljp.csp.versions' /> for details on the protocol version.", 'optional' => 1, } },
              );
     unshift (@{$mode->{'props'}->{'response'}}, 
              { 'name' => "success", 'props' => { 'des' => "<emphasis role='bold'><literal>OK</literal></emphasis> on success or <emphasis role='bold'><literal>FAIL</literal></emphasis> when there's an error.  When there's an error, see <literal>errmsg</literal> for the error text.  The absence of this variable should also be considered an error.", } },
              { 'name' => "errmsg", 'props' => { 'des' => "The error message if <literal>success</literal> was <literal>FAIL</literal>, not present if <literal>OK</literal>.  If the success variable isn't present, this variable most likely won't be either (in the case of a server error), and clients should just report \"Server Error, try again later.\".", } },
              );
     print "<refentry id=\"ljp.csp.flat.$name\">\n";
     print "  <refnamediv>\n    <refname>$name</refname>\n";
     print "    <refpurpose>$des</refpurpose>\n  </refnamediv>\n";

     print "  <refsect1>\n    <title>Mode Description</title>\n";
     print "    <para>$des</para>\n  </refsect1>\n";
     foreach my $rr (qw(request response)) 
     {
         print "<refsect1>\n";
         my $title = $rr eq "request" ? "Arguments" : "Return Values";
         print "  <title>$title</title>\n";
         print "  <variablelist>\n";
         foreach (@{$mode->{'props'}->{$rr}}) 
         {
             print "    <varlistentry>\n";
             cleanse(\$_->{'name'});
             print "      <term><literal>$_->{'name'}</literal></term>\n";
             print "      <listitem><para>\n";
             if ($_->{'props'}->{'optional'}) {
                 print "<emphasis>(Optional)</emphasis>\n";
             }
             cleanse(\$_->{'props'}->{'des'});
             print "$_->{'props'}->{'des'}\n";
             print "      </para></listitem>\n";
             print "    </varlistentry>\n";
         }
         print "  </variablelist>\n";
         print "</refsect1>\n";
     }
     print "</refentry>\n";
 }
