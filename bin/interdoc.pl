#!/usr/bin/perl

# This script parses LJ dependency info from all the other files on
# that make up the site.  Usually that dependency data is at the end
# of the files, but in this file it's here at the top for two reasons:
# as an example, and because otherwise this script would parse itself
# and start at the wrong place.  So, here's this file's dependency
# data:

# <LJDEP>
# lib: Getopt::Long
# </LJDEP>

# This file parses files for lines containing <LJDEP> then starts
# looking for dependency declarations on subsequent lines until
# </LJDEP> is found.  Note that leading junk is ignored.  The
# dependencies are of the form:

#    type: item, item, item

# Where type is one of "lib", "link", "form", "img".  lib is
# libraries.  link is an http GET links.  form is a POST submission
# targets.  img is an image.  There can be multiple declaration lines
# with the same type.  The results are just appended.  Perl modules
# should be delcared as Foo::Bar, but other files that are in the LJ
# doc tree are should be relative from $LJHOME, like htdocs/file.bml

use strict;
use Getopt::Long;

my $warn = 0;
GetOptions('warn' => \$warn);

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}
chdir $ENV{'LJHOME'} or die "Can't cd to $ENV{'LJOME'}\n";

find(qw(bin cgi-bin htdocs));

exit;

sub find
{
    my @dirs = @_;
    while (@dirs)
    {
	my $dir = shift @dirs;

	opendir (D, $dir);
	my @files = sort { $a cmp $b } readdir(D);
	close D;

	foreach my $f (@files) {
	    next if ($f eq "." || $f eq "..");
	    my $full = "$dir/$f";
	    if (-d $full) { find($full); }
	    elsif (-f $full) { check_file($full); }
	}
    }

}

sub check_file 
{
    $_ = shift;
    next unless (-f);
    next if (/\.(gif|jpg|png|class|jar|zip|exe)$/);
    next if (/~$/);

    my $file = $_;
    my $indep = 0;
    my %deps;

    open (F, $file);
    while (my $l = <F>)
    {
	if (! $indep) {
	    if ($l =~ /<LJDEP>/) {
		$indep = 1;
		$deps{'_found'} = 1;
	    }
	    next;
	}
	
	if ($l =~ /<\/LJDEP>/) {
	    last;
	}
	
	if ($l =~ /(\w+):(.+)/) {
	    my $k = $1;
	    my $v = $2;
	    $v =~ s/^\s+//;
	    $v =~ s/\s+$//;
	    my @vs = split(/\s*\,\s*/, $v);
	    foreach (@vs) {
		push @{$deps{$k}}, $_;
	    }
	}
    }

    if (delete $deps{'_found'})
    {
	foreach my $t (keys %deps) {
	    foreach my $v (@{$deps{$t}}) {
		print join("\t", $file, $t, $v), "\n";
	    }
	}
    }
    else 
    {
	if ($warn) {
	    print STDERR "No dep info: $file\n";
	}
    }

}
