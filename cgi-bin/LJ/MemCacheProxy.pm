package LJ::MemCacheProxy;

use strict;
use warnings;

use LJ::MemCache;

my %singletons = ();

sub reset_singletons {
    %singletons = ();
}

sub get {
    my ($key_origin) = @_;

    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    if (exists $singletons{$key}) {
        return $singletons{$key};
    }

    my $value = LJ::MemCache::get($key_origin);
    $singletons{$key} = $value;
    return $value;
}

sub get_multi {
    my @keys = @_;

    my $local_ret;
    my @keys_request = ();
    foreach my $key (@keys) {
        my $key_normal = ref $key eq 'ARRAY' ? $key->[1]
                                             : $key;

        if (exists $singletons{$key_normal}) {
            $local_ret->{$key_normal} = $singletons{$key_normal};
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
    my ($key_origin) = @_;

    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    delete $singletons{$key};
    LJ::MemCache::delete($key_origin);
}

sub set {
    my ($key_origin, $value, $expire) = @_;

    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    $singletons{$key} = $value;
    return LJ::MemCache::set($key_origin, $value, $expire);
}

sub replace {
    my ( $key_origin, $value, $expire ) = @_;

    my $key = $key_origin->[1]
        if ref $key_origin eq 'ARRAY';

    $singletons{$key} = $value;
    return LJ::MemCache::replace($key_origin, $value, $expire);
}

sub add {
    my ( $key_origin, $value, $expire ) = @_;
    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    $singletons{$key} = $value unless $singletons{$key};

    return LJ::MemCache::add($key_origin, $value, $expire);
}

1;

