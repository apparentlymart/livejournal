#!/usr/bin/perl

# This script parses LJ dependency info from all the other files on
# that make up the site.  Usually that dependency data is at the end
# of the files, but in this file it's here at the top for two reasons:
# as an example, and because otherwise this script would parse itself
# and start at the wrong place.  So, here's this file's dependency
# data:
#
# <LJDEP>
# lib: Getopt::Long
# </LJDEP>
#
# This file parses files for lines containing <LJDEP> then starts
# looking for dependency declarations on subsequent lines until
# </LJDEP> is found.  Note that leading junk is ignored.  The
# dependencies are of the form:
#
#    type: item, item, item
#
# Where type is one of:
#
#     file   -- data file
#     form   -- form with method=GET
#     lib    -- perl module or library (append :: if ! /::/)
#     link   -- web link
#     mailto -- mailto link
#     post   -- form with method=POST
#     prog   -- program that's run
#     hook   -- LJ hook name
#

use strict;
use Getopt::Long;

my $opt_warn = 0;
my $opt_types = 0;
GetOptions('warn' => \$opt_warn,
           'types' => \$opt_types);

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
        next if ($dir eq "htdocs/img");
        next if ($dir eq "htdocs/doc");

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
    next if (/\.(gif|jpg|png|class|jar|zip|exe|gz|deb|rpm|ico)$/);
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
    close (F);

    if (delete $deps{'_found'}) {
        foreach my $t (keys %deps) {
            foreach my $v (@{$deps{$t}}) {
                if ($opt_types) {
                    print "$t\n";
                } else {
                    print join("\t", $file, $t, $v), "\n";
                }
            }
        }
    } else {
        if ($opt_warn) {
            print STDERR "No dep info: $file\n";
        }
    }

}
