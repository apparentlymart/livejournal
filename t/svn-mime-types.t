#!/usr/bin/perl

use strict;
use Test::More;

my %check;
my @files = `$ENV{LJHOME}/bin/cvsreport.pl --map`;
foreach my $line (@files) {
    chomp $line;
    my ($rel, $path) = split(/\t/, $line);
    next unless $path =~ /\.(gif|jpe?g|png|ico)$/i;
    $check{$path} = 1;
}


plan tests => scalar keys %check;

my %badfiles;

foreach my $f (sort keys %check) {
    $f =~ s!^(\w+)/!!;
    my $dir = $1;
    chdir("$ENV{LJHOME}/cvs/$dir") or die;
    unless (-d ".svn") {
        ok(1, "$f: isn't svn");
        next;
    }
    my @props = `svn pl -v $f`;
    my %props;
    foreach my $line (@props) {
        next unless $line =~ /^\s+(\S+)\s*:\s*(.+)/;
        $props{$1} = $2;
    }

    my $mtype = $props{'svn:mime-type'} || "";
    my @errors;
    if ($props{'svn:eol-style'}) {
        push @errors, "EOL set";
    }
    if (! $mtype || $mtype =~ /^text/) {
        push @errors, "MIME=$mtype";
    }

    ok(! @errors, "$f: @errors");

    if (@errors) {
        $badfiles{$f} = \@errors;
    }
}

use Data::Dumper;
if (%badfiles) {
    warn Dumper(\%badfiles);
}
