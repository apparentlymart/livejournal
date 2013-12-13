package LJ::MemCacheProxy;

use strict;
use warnings;

# Internal modules
use LJ::MemCache;

my %singletons = ();

sub reset_singletons {
    %singletons = ();
}

sub set {
    my ($key_origin, $value, $expire) = @_;
    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    $singletons{$key} = $value;

    return LJ::MemCache::set($key_origin, $value, $expire);
}

sub add {
    my ($key_origin, $value, $expire) = @_;
    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    unless (exists $singletons{$key}) {
        $singletons{$key} = $value;
    }

    return LJ::MemCache::add($key_origin, $value, $expire);
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

sub delete {
    my ($key_origin) = @_;
    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    delete $singletons{$key};

    LJ::MemCache::delete($key_origin);
}

sub replace {
    my ( $key_origin, $value, $expire ) = @_;
    my $key = ref $key_origin eq 'ARRAY' ? $key_origin->[1] : $key_origin;

    $singletons{$key} = $value;

    return LJ::MemCache::replace($key_origin, $value, $expire);
}

sub set_multi {
    my @data = @_;

    foreach my $item (@data) {
        my $key = $item->[0];
        my $val = $item->[1];

        next unless $key;

        # Complex key only
        $key = $key->[1];

        next unless $key;

        $singletons{$key} = $val;
    }

    return LJ::MemCache::set_multi(@data);
}

sub get_multi {
    my @keys = @_;
    my $local_ret;
    my @keys_request = ();

    foreach my $key (@keys) {
        my $key_normal = ref $key eq 'ARRAY' ? $key->[1] : $key;

        if (exists $singletons{$key_normal}) {
            $local_ret->{$key_normal} = $singletons{$key_normal};
        } else {
            push @keys_request, $key;
        }
    }

    if (@keys_request) {
        my $ret = LJ::MemCache::get_multi( @keys_request );

        while (my ($key, $data) = each %$ret) {
            $singletons{$key}  = $data;
            $local_ret->{$key} = $data;
        }
    }

    return $local_ret;
}

1;
