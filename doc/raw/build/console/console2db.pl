#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/console.pl";
my $ret;

sub cleanse {
    my $text = shift;
    $text =~ s/&(?!(?:[a-zA-Z0-9]+|#\d+);)/&amp;/g;
    $text =~ s/<tt><b>(.+?)<\/b><\/tt>/<literal>$1<\/literal>/ig;
    $text =~ s/<b>(.+?)<\/b>/<literal>$1<\/literal>/ig;
    $text =~ s/<tt>(.+?)<\/tt>/<literal>$1<\/literal>/ig;
    return $text;
}

$ret .= "<variablelist><title>Administrative Console Commands</title>\n";
foreach my $cmdname (sort keys %LJ::Con::cmd) {
    my $cmd = $LJ::Con::cmd{$cmdname};
    next if ($cmd->{'hidden'});
    $ret .= "<varlistentry>\n";
    $ret .= "  <term><literal role=\"console.command\">$cmdname</literal></term>";
    my $des  = cleanse($cmd->{'des'});
    $ret .= "<listitem><para>$des";
    if ($cmd->{'args'}) {
        $ret .= "<itemizedlist>\n<title>Arguments:</title>\n";
        my @des = @{$cmd->{'args'}};
        while (my ($arg, $des) = splice(@des, 0, 2)) {
            $ret .= "<listitem><formalpara>";
            $ret .= "<title>$arg</title>\n";
            $des = cleanse($des); 
            $ret .= "<para>$des</para>\n";
            $ret .= "</formalpara></listitem>";
        }
        $ret .= "</itemizedlist>\n";
    }
    $ret .= "</para></listitem>\n";
    $ret .= "</varlistentry>\n";
}
$ret .= "</variablelist>\n";
print $ret;
