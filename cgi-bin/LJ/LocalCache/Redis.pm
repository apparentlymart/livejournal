package LJ::LocalCache::Redis;
use base(LJ::LocalCache);

use strict;
use warnings;

use Redis;

my $process_connection_id;
my $local_connection;
my $failed = 0;

sub __get_connection {
    my $class = shift;
    return undef if $failed; 

    if ($local_connection) {
        if ( $process_connection_id == $$ &&
             $local_connection->ping ) {
            return $local_connection;
        } else {
            $local_connection = undef;
        }
    }    

    $process_connection_id = $$;
    $local_connection = eval { Redis->new( encoding => undef,
                                           sock   => $LJ::LOCAL_REDIS_UNIX_SOCKET,
                                           debug => 0) };
   
    unless ($local_connection) {
        $failed = 1;  
        $class->__critical_error('LJ::LocalCache::Redis');     
 
        warn "connection error: $@"
            if $LJ::IS_DEV_SERVER;
    }

    return $local_connection;
}

sub get {
    my ($class, $key) = @_;
    my $connection = $class->__get_connection();
    if (!$connection) {
        return;
    }

    return $connection->get($key);
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;

    my $connection = $class->__get_connection();
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
    my $connection = $class->__get_connection();
    if (!$connection) {
        return 0;
    }

    my $result = $connection->set( $key, 
                                   $value);
    
    if ($expire) {
        $connection->expire($key, $expire);
    }

    return $result;
}

sub expire {
    my ($class, $key, $expire) = @_;
    my $connection = $class->__get_connection();
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
    my $connection = $class->__get_connection();

    if (!$connection) {
        return 0;
    }

    return $connection->del($key);
}

sub incr {
    my ($class, $key, $value) = @_;
    my $connection = $class->__get_connection();

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
    my $connection = $class->__get_connection();

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
    my $connection = $class->__get_connection();

    if (!$connection) {
        return 0;
    }

    return $connection->exists($key);
}

sub rpush {
    my ($class, $key, $value) = @_;
    my $connection = $class->__get_connection();

    if (!$connection) {
        return 0;
    }

    return $connection->rpush($key, $value);    
}

sub lpush {
    my ($class, $key, $value) = @_;
    my $connection = $class->__get_connection();

    if (!$connection) {
        return 0;
    }

    return $connection->lpush($key, $value);
}

sub lpop {
    my ($class, $key) = @_;
    my $connection = $class->__get_connection();

    if (!$connection) {
        return undef;
    }

    return $connection->lpop($key);
}

sub rpop {
    my ($class, $key) = @_;
    my $connection = $class->__get_connection();

    if (!$connection) {
        return undef;
    }

    return $connection->rpop($key);
}

1;

