package LJ::LocalCache::BerkeleyDB;
use base(LJ::LocalCache);

use strict;
use warnings;

use BerkeleyDB;
use File::Path;

my $connection;
my $lifetime;

sub __reset_connection {
    if ($connection) {
        $connection->db_close();
        $connection = undef;
    }
}

sub __get_instance {
    my ($class) = @_;

    if ($connection) {
        die "CDS is not enabled " 
            unless $connection->cds_enabled();
        return $connection;
    }

    return unless LJ::is_web_context();
    unless(-d $LJ::LJ_LOCAL_BDB_HOME) {
        mkdir $LJ::LJ_LOCAL_BDB_HOME, 0755;
    }

    my $db_file_name = "$LJ::LJ_LOCAL_BDB_HOME/$LJ::LJ_LOCAL_BDB_NAME";
    if (-e $db_file_name) {
        my $status = BerkeleyDB::db_verify( -Filename => $db_file_name, );
#                                            -Outfile => $db_file_name);

        if ($status) {
            rmtree($LJ::LJ_LOCAL_BDB_HOME);
            mkdir $LJ::LJ_LOCAL_BDB_HOME, 0755;
        }
    }   

    my $env = new BerkeleyDB::Env
                  -Home   => $LJ::LJ_LOCAL_BDB_HOME,
                  -Flags  => DB_CREATE| DB_INIT_CDB | DB_INIT_MPOOL,
                  -LockDetect => DB_LOCK_OLDEST,
                  -ErrFile => *STDERR
        or die "Environment error: $BerkeleyDB::Error\n";

    return unless $env;
    
    die "CDS is not enabled " unless $env->cds_enabled();
   
    my $status = $env->set_timeout(1, DB_SET_LOCK_TIMEOUT);
    if ($status) {
        die "set_timeout error $status" if $status;
    } 

    $connection = new BerkeleyDB::Hash
                               -Filename => $LJ::LJ_LOCAL_BDB_NAME,
                               -Flags    => DB_CREATE,
                               -Nelem    => 400,
                               -Env      => $env;

    if (!$connection) {
        rmtree($LJ::LJ_LOCAL_BDB_HOME);
        return;
    }

    return $connection;
}

sub get {
    my ($class, $key) = @_;

    my $db = $class->__get_instance();
    return unless $db;

    my $data = '';
    my $status = $db->db_get($key, $data);
    if ($status) {
        return undef;
    }

    my @parts  = split(/:/, $data, 2);

    if (@parts) {
        my $expire  = int($parts[0]);
        my $data    = $parts[1];

        if ($expire > time()) {
            return $data;
        }
    }

    return undef;
}

sub get_multi {
    my ($class, $keys, $not_fetched_keys) = @_;

    my $db = $class->__get_instance();
    return unless $db;

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

    $data ||= '';
    $expire ||= 10 * 60;
    my $expire_time = time() + $expire; 
    my $cache_data = "$expire_time:$data";

    my $db = $class->__get_instance();
    return unless $db;

    my $status = $db->db_put($key, $cache_data);
    if ($status) {
        return 0;
    }

    return 1;
}

sub replace {
    my ($class, $key, $value, $expire) = @_;
    return $class->set($key, $value, $expire);
}

sub delete {
    my ($class, $key) = @_;
    my $db = $class->__get_instance();
    return unless $db;

    my $status = $db->db_del($key);
    if ($status) {
        return 0;
    }
    return 1;
}

1;

