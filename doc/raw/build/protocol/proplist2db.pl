#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbr = LJ::get_dbh("slave", "master");
my $sth;

my $sth = $dbr->prepare("SELECT * FROM logproplist ORDER BY sortorder");
$sth->execute;

print "<variablelist>\n";
print "  <title>Log Prop List</title>\n\n";

while (my $r = $sth->fetchrow_hashref)
{
    print "  <varlistentry>\n";
    print "    <term><literal role='log.prop'>$r->{'name'}</literal></term>\n";
    print "    <listitem><formalpara><title>$r->{'prettyname'}</title>\n";
    print "    <para>$r->{'des'}</para>\n";
    print "      <itemizedlist>\n";
    print "        <listitem><formalpara><title>Datatype</title>\n";
    print "        <para>$r->{'datatype'}</para>\n";
    print "        </formalpara></listitem>\n";
    print "        <listitem><formalpara><title>Scope</title>\n";
    print "        <para>$r->{'scope'}</para>\n";
    print "        </formalpara></listitem>\n";
    print "      </itemizedlist>\n";
    print "    </formalpara></listitem>\n";
    print "  </varlistentry>\n\n";
}

print "</variablelist>\n";
