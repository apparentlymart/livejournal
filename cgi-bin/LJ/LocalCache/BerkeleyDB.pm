package LJ::LocalCache::BerkeleyDB;
use base(LJ::LocalCache);

use strict;
use warnings;

use BerkeleyDB;

my $connection;
my $lifetime;

sub __reset_connection {
    if ($connection) {
        $connection->db_close();
        $connection = undef;
    }
}

sub DESTROY {
    __reset_connection();
}

sub __get_instance {
    my ($class) = @_;

    if ($connection) {
        die "CDS is not enabled " 
            unless $connection->cds_enabled();
        return $connection;
    }

    unless(-d $LJ::LJ_LOCAL_BDB_HOME) {    
        mkdir $LJ::LJ_LOCAL_BDB_HOME;
    }

    my $env = new BerkeleyDB::Env
                  -Home   => $LJ::LJ_LOCAL_BDB_HOME,
                  -Flags  => DB_CREATE| DB_INIT_CDB | DB_INIT_MPOOL,
                  -LockDetect => DB_LOCK_OLDEST,
                  -ErrFile => *STDERR
        or die "cannot open environment: $BerkeleyDB::Error\n";

    return unless $env;
    die "CDS is not enabled " unless $env->cds_enabled();

    $connection = new BerkeleyDB::Hash
                    -Filename => $LJ::LJ_LOCAL_BDB_NAME,
                    -Flags    => DB_CREATE,
                    -Nelem    => 400,
                    -Env      => $env,
                or die "Cannot open file " . $LJ::LJ_LOCAL_BDB_NAME .
                        ": $! $BerkeleyDB::Error\n";

    return $connection;
}

sub get {
    my ($class, $key) = @_;

    my $db = $class->__get_instance();
    return unless $db;

    my $data = '';
    my $status = $db->db_get($key, $data);
    my @parts  = split(/:/, $data, 2);

    if (@parts) {
        my $expire  = int($parts[0]);
        my $data    = $parts[1];

        if ($expire > time()) {
            return $data;
        }

        my $lock = $db->cds_lock();
        unless ($lock) {
            __reset_connection();
            return;
        }

        eval { $db->db_del($key); };
        $lock->cds_unlock();
    }

    return undef;
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;

    my $result = {};
    foreach my $key (@$keys) {
        my $res = $class->get($key);
        if ($res) {
            $result->{$key} = $res;
        } elsif ($not_fetched_keys) {
            push @{$not_fetched_keys}, $key;
        }
    }
    return $result;
}

sub set {
    my ($class, $key, $data, $expire) = @_;

    $expire ||= 10 * 60;
    my $expire_time = time() + $expire; 
    my $cache_data = "$expire_time:$data";

    my $db = $class->__get_instance();
    return unless $db;

    my $lock = $db->cds_lock();
    unless ($lock) {
        __reset_connection();
        return 0;
    }   

    eval { $db->db_put($key, $cache_data); };
    $lock->cds_unlock();

    return 1;
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return 0;
}

sub delete {
    my ($class, $key) = @_;
    my $db = $class->__get_instance();
    return unless $db;

    my $lock = $db->cds_lock();
    unless ($lock) {
        __reset_connection();
        return  0;
    }

    eval { $db->db_del($key); };
    $lock->cds_unlock();
    return 1;
}

1;

