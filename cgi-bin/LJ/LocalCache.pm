package LJ::LocalCache;

use strict;
use warnings;

use LJ::ModuleLoader;

# Usage example: 
#   
#   LJ::LocalCache::get_cache()->set("ml.${lncode}.${dmid}.${itcode}", $text, 30*60);
#


my @SUBCLASSES = LJ::ModuleLoader->module_subclasses(__PACKAGE__);
my %modules_info;
my $loaded = 0;

use constant {
    LOAD_SUCCESSFUL => 1,
    LOAD_FAILED     => -1,
    NOT_LOADED      => 0,
    CRITICAL_ERROR  => 2,
};

sub __load_packages {
    return if $loaded;

    if (LJ::is_enabled("local_cache")) {
        %modules_info = map { $_ => NOT_LOADED } @SUBCLASSES;
        $loaded = 1;
    }
}

# this function will disable a module from using 
# even it is already loaded
sub __critical_error {
    my $module = shift;
    $modules_info{$module} = CRITICAL_ERROR;
}

sub __get_package { 
    my $module = shift;
    my $status = $modules_info{$module};
    
    return "LJ::LocalCache::$module" if $status == LOAD_SUCCESSFUL;
    return 'LJ::LocalCache' if $status == LOAD_FAILED ||
                               $status == CRITICAL_ERROR;

    # try to load
    eval  "use $module" ;

    if ($@) {
        $modules_info{$module} = LOAD_FAILED;
        return 'LJ::LocalCache';
    }
 
    return $module;
}

sub get_cache {
    my ($handler) = @_;
    $handler ||= $LJ::LOCAL_CACHE_DEFAULT_HANDLER;

    return 'LJ::LocalCache' if !LJ::is_enabled("local_cache");
    __load_packages();
    return __get_package("LJ::LocalCache::$handler"); 
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

