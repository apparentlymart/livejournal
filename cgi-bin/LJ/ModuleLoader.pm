#!/usr/bin/perl

package LJ::ModuleLoader;

use strict;
require Exporter;
use vars qw(@ISA @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(module_subclasses);

# given a module name, looks under cgi-bin/ for its patch and, if valid,
# returns (assumed) package names of all modules in the directory
sub module_subclasses {
    shift if @_ > 1; # get rid of classname
    my $base_class = shift;
    my $base_path  = "$ENV{LJHOME}/cgi-bin/" . join("/", split("::", $base_class));
    die "invalid base: $base_class" unless -d $base_path;

    return map {
        s!.+cgi-bin/!!;
        s!/!::!g;
        s/\.pm$//;
        $_;
    } (glob "$base_path/*.pm");
}

sub autouse_subclasses {
    shift if @_ > 1; # get rid of classname
    my $base_class = shift;

    foreach my $class (LJ::ModuleLoader->module_subclasses($base_class)) {
        eval "use Class::Autouse qw($class)";
        die "Error loading $class: $@" if $@;
    }
}

# FIXME: This should do more...

1;
