package LJ::ModuleCheck;
use strict;
use warnings;

my %have;

sub have {
    my ($class, $modulename) = @_;
    return $have{$modulename} if exists $have{$modulename};
    die "Bogus module name" unless $modulename =~ /^[\w:]+$/;
    return $have{$modulename} = eval "use $modulename (); 1;";
}

1;
