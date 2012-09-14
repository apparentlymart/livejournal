package LJ::LocalCache::Redis;
use base(LJ::LocalCache);

use strict;
use warnings;

my $local_connection;
my $master_connection;

sub __get_read_connection {
    if ($local_connection) {
        return $local_connection;
    }
     
    $local_connection = eval { Redis->new(encoding => undef) };
    if ($@ && $LJ::IS_DEV_SERVER) {
        warn "get read connection error: $@";
    }

    return $local_connection;
}

sub __get_write_conneciton {
    if ($master_connection) {
        return $master_connection;
    }   

    $master_connection = eval { Redis->new(
        server => $LJ::MASTER_REDIS_LIGTH_CACHE,
        debug  => 0,
        encoding => undef); 
    };
    
    if ($@ && $LJ::IS_DEV_SERVER) {
        warn "get write conenction error: $@" if $LJ::IS_DEV_SERVER;
        return;
    }

    return $master_connection;
}

sub get {
    my ($class,$key) = @_;
    my $connection = __get_read_connection();
    if (!$connection) {
        return;
    }

    return $connection->get($key);
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;

    my $connection = __get_read_connection();
    if (!$connection) {
        @$not_fetched_keys = @$keys;
        return;
    }

    my @data = $connection->mget(@$keys);
    
    my $result;
    foreach my $key (@$keys) {
        my $value = shift @data;

        if ($value) {
            $result->{$key} = $value; 
        } else {
            push @{$not_fetched_keys}, $key;
        }
    }

   return $result;
}

sub set {
    my ($class, $key, $value, $expire) = @_;
    my $connection = __get_write_conneciton();
    if (!$connection || !$value) {
        return 0;
    }

    my $result = $connection->set( $key, 
                                   $value );
    $connection->expire($key, $expire);
    return $result;
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return $class->set($key);
}

sub delete {
    my ($class, $key) = @_;
    return undef;
}

1;


