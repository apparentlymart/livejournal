package LJ::LocalCache;
use strict;
use warnings;

use LJ::ModuleLoader;

my @SUBCLASSES = LJ::ModuleLoader->module_subclasses(__PACKAGE__);

my $loaded = 0;

sub __load_packages {
    return if $loaded;
    if (LJ::is_enabled("local_cache")) {
        foreach my $class (@SUBCLASSES) {
            eval "use $class";
            if ($@) {
                warn "Error loading package $class: $@" 
            }
        }

        $loaded = 1;
    }
}

sub get_cache {
    my ($handler) = @_;
    $handler ||= $LJ::LOCAL_CACHE_DEFAULT_HANDLER;

    return 'LJ::LocalCache' if !LJ::is_enabled("local_cache");
    __load_packages();
    return "LJ::LocalCache::$handler";
}

sub get {
    my ($class,$key) = @_;
    return undef;
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;
    $not_fetched_keys = $keys;
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

