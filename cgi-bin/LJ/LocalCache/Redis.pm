package LJ::LocalCache::Redis;
use base(LJ::LocalCache);

use strict;
use warnings;

use utf8;
use Redis;

my $local_connection;
my $master_connection;

sub __get_read_connection {
    if ($local_connection) {
        if ($local_connection->ping) {
            return $local_connection;
        } else {
            $local_connection = undef;
        }
    }    

    if ($local_connection) {
        $local_connection = undef
            unless $local_connection->ping;
        return $local_connection;
    }
     
    $local_connection = eval { Redis->new(encoding => undef, 
                                          debug => 0) };
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

    my $value = $connection->get($key);

    return unless $value;
    return utf8::encode($value);
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
            $result->{$key} = utf8::encode($value); 
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
                                   utf8::decode($value) );

    if ($expire) {
        $connection->expire($key, $expire);
    }

    return $result;
}

sub expire {
    my ($class, $key, $expire) = @_;
    my $connection = __get_write_conneciton();
    if (!$connection) {
        return 0;
    }

    return $connection->expire($key, $expire);
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return $class->set($key);
}

sub delete {
    my ($class, $key) = @_;
    my $connection = __get_write_conneciton();

    if (!$connection) {
        return 0;
    }

    return $connection->del($key);
}

sub incr {
    my ($class, $key, $value) = @_;
    my $connection = __get_write_connection();

    if (!$connection) {
        return 0;
    }

    if ($value) {
        $value = int($value);
        return 0 unless $value;
        return $connection->incrby($key, $value);
    }
    return $connection->incr($key);
}

sub decr {
    my ($class, $key, $value) = @_;
    my $connection = __get_write_connection();

    if (!$connection) {
        return 0;
    }

    if ($value) {
        $value = int($value);
        return 0 unless $value;
        return $connection->decrby($key, $value);
    }

    return $connection->decr($key);
}

sub exists {
    my ($class, $key) = @_;
    my $connection = __get_read_connection();

    if (!$connection) {
        return 0;
    }

    return $connection->exists($key);
}

sub rpush {
    my ($class, $key, $value) = @_;
    my $connection = __get_write_connection();

    if (!$connection) {
        return 0;
    }

    $value = utf8::decode($value);
    return $connection->rpush($key, $value);    
}

sub lpush {
    my ($class, $key, $value) = @_;
    my $connection = __get_write_connection();

    if (!$connection) {
        return 0;
    }

    $value = utf8::decode($value);
    return $connection->lpush($key, $value);
}

sub lpop {
    my ($class, $key) = @_;
    my $connection = __get_read_connection();

    if (!$connection) {
        return undef;
    }

    my $value = $connection->lpop($key);
    return unless $value;
    return unf8::encode($value);
}

sub rpop {
    my ($class, $key) = @_;
    my $connection = __get_read_connection();

    if (!$connection) {
        return undef;
    }

    my $value = $connection->rpop($key);
    return unless $value;
    return unf8::encode($value);
}

1;


