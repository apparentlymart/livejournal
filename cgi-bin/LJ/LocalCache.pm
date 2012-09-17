package LJ::LocalCache;
use strict;
use warnings;

use LJ::ModuleLoader;

# Usage example: 
#   
#   LJ::LocalCache::get_cache()->set("ml.${lncode}.${dmid}.${itcode}", $text, 30*60);
#


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

sub expire {
    my ($class, $key, $expire) = @_;
    return 0;
}

sub get {
    my ($class, $key) = @_;
    return undef;
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;
    @$not_fetched_keys = @$keys;
    return undef;
}

sub set {
    my ($class, $key, $value, $expire) = @_;
    return undef;
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return 0;
}

sub delete {
    my ($class, $key) = @_;
    return 0;
}

sub incr {
    my ($class, $key, $value) = @_;
    return 0;
}

sub decr {
    my ($class, $key, $value) = @_;
    return 0;
}

sub exists {
    my ($class, $key) = @_;
    return 0;
}

sub rpush {
    my ($class, $key, $value) = @_;
    return 0;
}

sub lpush {
    my ($class, $key, $value) = @_;
    return 0;
}

sub lpop {
    my ($class, $key) = @_;
    return undef;
}

sub rpop {
    my ($class, $key) = @_;
    return undef;
}

1;

