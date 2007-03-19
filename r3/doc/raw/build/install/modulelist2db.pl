#!/usr/bin/perl
#

use strict;

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

my $LJHOME = $ENV{'LJHOME'};
my (%modules, @debs, $line);
require "$LJHOME/doc/raw/build/docbooklib.pl";
require "$LJHOME/cgi-bin/ljlib.pl";

my @modules;
my $indoc; my $curmod;
open (CFG, "$LJHOME/bin/checkconfig.pl") or return 0;
while ($line = <CFG>)
{
    $line = LJ::trim($line);
    next if $line =~ /^\},/;
    if ($line =~ /\Qmy %modules\E/) { $indoc = 1; next; }
    if ($indoc && $line =~ /\Q);\E/) { $indoc = 0; next; }
    if ($indoc) { 
        if ($line =~ /^\"(.+?)\"/) {
            push @modules, $curmod if $curmod->{'name'}; 
            $curmod = {};
            $curmod->{'name'} = $1;
        }
        if ($line =~ /\'deb\' \=> \'(.+?)\'/) { $curmod->{'deb'} = $1; }
        if ($line =~ /^\'opt\' \=> [\'\"](.+?)[\'\"]/) { $curmod->{'opt'} = $1; }
    } elsif ($curmod->{'name'}) { 
        push @modules, $curmod if $curmod->{'name'}; 
        $curmod = {};
    }
}
close CFG;

# Print reference

print "<table frame='none'>\n  <title>Required Modules</title>\n";
print "  <tgroup cols='2'>\n    <tbody>\n";
foreach my $module ( @modules )
{
    print "      <row><entry>$module->{'name'}</entry><entry>$module->{'deb'}</entry></row>\n" unless $module->{'opt'};
}
print "    </tbody>\n  </tgroup>\n</table>";
print "<variablelist>\n  <title>Optional modules</title>\n";
foreach my $module ( @modules )
{
    print "  <varlistentry><term>$module->{'name'}</term><term>$module->{'deb'}</term><listitem><simpara>$module->{'opt'}</simpara></listitem></varlistentry>\n" if $module->{'opt'};
}
print "</variablelist>";

print "<formalpara><title>Debian Install</title><para>";
print "If you're using Debian the following command should retrieve and build every required module:</para></formalpara>";
print "<screen><prompt>#</prompt> <userinput>apt-get install ";
my $i = 0;
foreach my $module ( @modules ) {
    next if $module->{'opt'};
    if ($i == 3) { print "\\\n"; $i = 0; } $i++;
    print "$module->{'deb'} ";
}
print "</userinput></screen>

<simpara>And likewise for the optional modules:</simpara>

<screen><prompt>#</prompt> <userinput>apt-get install ";
$i = 0;
foreach my $module ( @modules ) {
    next unless $module->{'opt'};
    if ($i == 3) { print "\\\n"; $i = 0; } $i++;
    print "$module->{'deb'} ";
}

print "</userinput></screen>

<formalpara>
  <title>Using CPAN</title>
  <para>
    Otherwise you'll want to use CPAN to install the modules by performing the following steps:
  </para>
</formalpara>
<simpara>From the root prompt on your server, invoke the CPAN shell:</simpara>
<screen><prompt>#</prompt> <userinput>perl -MCPAN -e shell</userinput></screen>

<simpara>
  Once the Perl interpreter has loaded (and been configured), you can install
   modules by issuing the command <literal>install <replaceable>MODULENAME</replaceable></literal>.
</simpara>
<simpara>The first thing you should do is upgrade your CPAN:</simpara>

<screen><prompt>cpan></prompt> <userinput>install Bundle::CPAN</userinput></screen>

<simpara>Once it's done, type:</simpara>

<screen><prompt>cpan></prompt> <userinput>reload cpan</userinput></screen>

<simpara>Now, enter the following command to retrieve all of the required modules:</simpara>

<screen>";
foreach my $module ( @modules ) {
    print "<prompt>cpan></prompt> <userinput>install $module->{'name'}</userinput>\n" unless $module->{'opt'};
}
print "</screen>
<simpara>And likewise for the optional modules:</simpara>

<screen>";
foreach my $module ( @modules ) {
    print "<prompt>cpan></prompt> <userinput>install $module->{'name'}</userinput>\n" if $module->{'opt'};
}
print "</screen>";
