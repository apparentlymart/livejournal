#!/usr/bin/perl

# This script parses LJ function info from all the library files 
# that make up the site.  See cgi-bin/ljlib.pl for an example
# of the necessary syntax.

use strict;
use Getopt::Long;
use Data::Dumper;

my $opt_warn = 0;
my $opt_types = 0;
GetOptions('warn' => \$opt_warn,
	   'types' => \$opt_types);

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}
chdir $ENV{'LJHOME'} or die "Can't cd to $ENV{'LJOME'}\n";

my %funcs;
find(qw(cgi-bin));

print Dumper(\%funcs);

exit;

sub find
{
    my @dirs = @_;
    while (@dirs)
    {
	my $dir = shift @dirs;
	next if ($dir eq "htdocs/img");

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
    my $infunc = 0;
    my $f;                # the current function info we're loading

    my $prefix;
    my $curkey;
    my $contlen;

    open (F, $file);
    while (my $l = <F>)
    {
	if (! $infunc) {
	    if ($l =~ /<LJFUNC>/) {
		$infunc = 1;
		$f = {};
	    }
	    next;
	}
	
	if ($l =~ /<\/LJFUNC>/) {
	    $infunc = 0;
	    $prefix = "";
	    $curkey = "";
	    $contlen = 0;
	    if ($f->{'name'}) {
		$funcs{$f->{'name'}} = $f;
		treeify($f);
	    }
	    next;
	}
	
	# continuing a line from line before... must have 
	# same indenting.
	if ($prefix && $contlen) {
	    my $cont = $prefix . " "x$contlen;
	    if ($l =~ /^\Q$cont\E(.+)/) {
		my $v = $1;
		$v =~ s/^\s+//;
		$v =~ s/\s+$//;
		$f->{$curkey} .= " " . $v;
		next;
	    }
	}
	
	if ($l =~ /^(\W*)([\w\-]+)(:\s*)(.+)/) {
	    $prefix = $1;
	    my $k = $2;
	    my $v = $4;
	    $v =~ s/^\s+//;
	    $v =~ s/\s+$//;
	    $f->{$k} = $v;
	    $curkey = $k;
	    $contlen = length($2) + length($3);
	}
    }
    close (F);

}

sub treeify
{
    my $f = shift;
    my $args = $f->{'args'};
    $f->{'args'} = [];

    $args =~ s/\s+//g;
    foreach my $arg (split(/\,/, $args))
    {
	my $opt = 0;
	if ($arg =~ s/\?$//) { $opt = 1; }
	my $list = 0;
	if ($arg =~ s/\*$//) { $list = 1; }
	my $a = { 'name' => $arg };
	if ($opt) { $a->{'optional'} = 1; }
	if ($list) { $a->{'list'} = 1; }
	$a->{'des'} = $f->{"des-$arg"};
	delete $f->{"des-$arg"};
	push @{$f->{'args'}}, $a;
    }
    
      
}
