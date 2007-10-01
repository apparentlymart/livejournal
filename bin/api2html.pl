#!/usr/bin/perl
#

use strict;

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}
chdir $ENV{'LJHOME'} or die "Can't cd to $ENV{'LJOME'}\n";

### apidoc.pl does all the hard work.
my $VAR1;
eval `bin/apidoc.pl`;
my $api = $VAR1;

print "<html>\n";
print "<head><title>LiveJournal API Documentation</title></head>\n";
print "<body>\n";
print "<h1>LiveJournal API Documentation</h1>\n";

## print list
print "<h2>Alphabetic List of Functions</h2>\n";
print "<ul>\n";
foreach my $func (sort keys %$api) {
    print "<li><a href=\"#$func\"><tt>$func</tt></a></li>\n";
}
print "</ul>\n";

## print each function
print "<h2>Function Descriptions</h2>\n";
foreach my $func (sort keys %$api) {
    my $f = $api->{$func};
    my $argstring;
    xlinkify(\$f->{'des'});

    my $optcount;
    foreach my $arg (@{$f->{'args'}}) {
        my $comma = $argstring ? ", " : "";
        my $lbrack = "";
        if ($arg->{'optional'}) { 
            $optcount++;
            $lbrack = "["	    
        }
        $argstring .= "$lbrack$comma$arg->{'name'}";
        if ($arg->{'list'}) {
            $argstring .= "*";
        }
    }
    $argstring .= "]"x$optcount;

    print "<a name=\"$func\">\n";
    print "<h3><tt>$func</tt></h3>\n";
    print "<blockquote><table>\n";

    print "<tr valign=\"top\"><td align=\"right\"><i>Description:</i></td>\n";
    print "<td>$f->{'des'}</td></tr>\n";

    print "<tr valign=\"bottom\"><td align=\"right\"><i>Source:</i></td>\n";
    print "<td><tt>$f->{'source'}</tt></td></tr>\n";

    if (@{$f->{'args'}}) {
        print "<tr valign=\"bottom\"><td align=\"right\"><i>Arguments:</i></td>\n";
        print "<td><tt><b>$argstring</b></tt></td></tr>\n";
        
        print "<tr valign=\"bottom\"><td>&nbsp;</td>\n";
        print "<td><table cellpadding=\"2\" border=\"1\">\n";
        foreach my $arg (@{$f->{'args'}}) {
            print "<tr valign=\"top\"><td>$arg->{'name'}</td>";
            my $des = $arg->{'des'};
            xlinkify(\$des);
            print "<td>$des</td></tr>\n";
        }
        print "</table></td></tr>\n";
    }
        
    if ($f->{'returns'}) {
        xlinkify(\$f->{'returns'});
        print "<tr valign=\"top\"><td align=\"right\"><i>Returns:</i></td>\n";
        print "<td>$f->{'returns'}</td></tr>\n";
    }
    
    print "</table></blockquote>\n";
    print "</a><hr>\n";
}


print "</body>\n";
print "</html>\n";

sub xlinkify {
    my $a = shift;
    $$a =~ s/\[func\[([^\]]*)]\]/<tt><a href=\"\#$1\">$1<\/a><\/tt>/g;
}
