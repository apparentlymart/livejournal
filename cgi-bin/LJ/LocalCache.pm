package LJ::LocalCache;
use strict;
use warnings;

use LJ::ModuleLoader;

my @SUBCLASSES = LJ::ModuleLoader->module_subclasses(__PACKAGE__);

foreach my $class (@SUBCLASSES) {
    eval "use $class";
    if ($@) {
        die "Error loading package $class: $@" 
    }
}

sub get_cache {
    my ($handler) = @_;
    $handler ||= $LJ::LOCAL_CACHE_DEFAULT_HANDLER;

    return "LJ::LocalCache::$handler";
}

sub get {
    my ($class,$key) = @_;
    return undef;
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;
    return undef;
}

sub set {
    my ($class, @keys) = @_;
    return undef;
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return undef;
}

sub delete {
    my ($class, $key) = @_;
    return undef;
}

1;

