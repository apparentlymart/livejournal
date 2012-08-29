package LJ::MemCacheProxy;

use strict;
use warnings;

use LJ::MemCache;

my %singletons = ();

sub reset_singletons {
    %singletons = ();
}

sub get {
    my ($key) = @_;

    $key = $key->[1]
        if ref $key eq 'ARRAY';
    
    if (exists $singletons{$key}) {
        return $singletons{$key};
    }

    my $value = LJ::MemCache::get($key);
    $singletons{$key} = $value;
    return $value;
}

sub get_multi {
    my @keys = @_;

    my $local_ret;
    my @keys_request = ();
    foreach my $key (@keys) {
        if (exists $singletons{$key}) {
            $local_ret->{$key} = $singletons{$key};
        } else {
            push @keys_request, $key;
        }
    }

    if (@keys_request) {
        my $ret = LJ::MemCache::get_multi( @keys_request );
        while (my ($key, $data) = each %$ret) {
            $singletons{$key} = $data;
            $local_ret->{$key} = $data;
        }
    }

    return $local_ret;
}

sub delete {
    my ($key) = @_;

    $key = $key->[1]
        if ref $key eq 'ARRAY';

    delete $singletons{$key};
    LJ::MemCache::delete($key);
}

sub set {
    my ($key, $value, $expire) = @_;

    $key = $key->[1]
        if ref $key eq 'ARRAY';

    $singletons{$key} = $value;
    return LJ::MemCache::set($key, $value, $expire);
}

sub replace {
    my ( $key, $value, $expire ) = @_;

    $key = $key->[1]
        if ref $key eq 'ARRAY';

    $singletons{$key} = $value;
    return LJ::MemCache::replace($key, $value, $expire);
}

1;

