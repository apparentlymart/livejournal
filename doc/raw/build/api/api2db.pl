#!/usr/bin/perl
#

use strict;
use Getopt::Long;

my ($opt_include, $opt_exclude);
die unless GetOptions(
                      'include=s' => \$opt_include,
                      'exclude=s' => \$opt_exclude,
		      );
die "Unknown arguments.\n" if @ARGV;
die "Can't exclude and include at same time!\n" if $opt_include && $opt_exclude;

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

chdir $ENV{'LJHOME'} or die "Can't cd to $ENV{'LJOME'}\n";

### apidoc.pl does all the hard work.
my $VAR1;
my $param;
$param = "--include=$opt_include" if $opt_include;
$param = "--exclude=$opt_exclude" if $opt_exclude;
eval `$ENV{'LJHOME'}/bin/apidoc.pl $param`;
my $api = $VAR1;

if ($opt_include) {
    my $package = lc($opt_include);
    $package =~ s/:://g;
    print "<reference id=\"ljp.$package.api.ref\">\n";
} else {
    print "<reference id=\"ljp.api.ref\">\n";
} 
print "  <title>API Documentation</title>\n";

foreach my $func (sort keys %$api) {
    my $f = $api->{$func};
    my $argstring;
    xlinkify(\$f->{'des'});

    my $canonized = canonize("func" , $func);
    print "  <refentry id=\"$canonized\">\n";

    ### name and short description:
    cleanse(\$f->{'des'});
    print "    <refnamediv>\n";
    print "      <refname>$func</refname>\n";
    print "      <refpurpose>$f->{'des'}</refpurpose>\n";
    print "    </refnamediv>\n";

    ### usage:
    print "    <refsynopsisdiv>\n";
    print "      <title>Use</title>\n";
    print "      <funcsynopsis>\n";
    print "        <funcprototype>\n";
    print "          <funcdef><function>$func</function></funcdef>\n";
    if (@{$f->{'args'}}) {
        foreach my $arg (@{$f->{'args'}}) {
            print "          <paramdef><parameter>$arg->{'name'}</parameter></paramdef>\n";
        }
    }
    print "        </funcprototype>\n";
    print "      </funcsynopsis>\n";
    print "    </refsynopsisdiv>\n";

    ### arguments:
    if (@{$f->{'args'}}) {
        print "    <refsect1>\n";
        print "      <title>Arguments</title>\n";
        print "      <itemizedlist>\n";
        
        foreach my $arg (@{$f->{'args'}}) {
            print "        <listitem><formalpara>\n";
            print "          <title>$arg->{'name'}</title>\n";
            my $des = $arg->{'des'};
            cleanse(\$des);
            xlinkify(\$des);
            print "          <para>$des</para>\n";
            print "        </formalpara></listitem>\n";
        }
        print "      </itemizedlist>\n";
        print "    </refsect1>\n";
    }

    ### info:
    if ($f->{'info'}) {
        cleanse(\$f->{'info'});
        xlinkify(\$f->{'info'});
        print "    <refsect1>\n";
        print "      <title>Info</title>\n";
        print "      <para>$f->{'info'}</para>\n";
        print "    </refsect1>\n";
    }

    ### source file:
    print "    <refsect1>\n";
    print "      <title>Source:</title>\n";
    print "      <para><filename>$f->{'source'}</filename></para>\n";
    print "    </refsect1>\n";
    
    ### returning:
    if ($f->{'returns'}) {
        cleanse(\$f->{'returns'});
        xlinkify(\$f->{'returns'});
        print "    <refsect1>\n";
        print "      <title>Returns:</title>\n";
        print "      <para>$f->{'returns'}</para>\n";
        print "    </refsect1>\n";
    }
    
    print "  </refentry>\n";
}


print "</reference>\n";

sub cleanse {
    my $text = shift;
    ### convert any ampersand that is not followed by [a-zA-Z0-9]+; or #\d+; to &amp;
    $$text =~ s/&(?!(?:[a-zA-Z0-9]+|#\d+);)/&amp;/g;
    ### "<b>Note:</b>" in source turns to <emphasis role='bold'>Note:</emphasis> in docbook
    $$text =~ s/<b>(.+?)<\/b>/<emphasis role='bold'>$1<\/emphasis>/ig;
}

sub xlinkify {
    my $a = shift;
    $$a =~ s/\[(\S+?)\[(\S+?)\]\]/"<link linkend='" . canonize($1, $2) . "'>$2<\/link>"/ge;
}

sub canonize {
    my $type = shift;
    my $string = lc(shift);
    if ($type eq "func") { 
        $string =~ s/::/./g;
        $string = "ljp.api.$string";
    } elsif($type eq "dbtable") {
        $string = "ljp.dbschema.$string";
    }
}

