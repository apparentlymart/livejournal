#
# Wrapper around MemCachedClient

use lib "$ENV{'LJHOME'}/cgi-bin";
use MemCachedClient;

package LJ::MemCache;

my $memc;

sub init {
    $memc = new MemCachedClient;
    trigger_bucket_reconstruct();
}

sub trigger_bucket_reconstruct {
    $memc->set_servers(\@LJ::MEMCACHE_SERVERS);
    $memc->set_debug($LJ::MEMCACHE_DEBUG);
    return $memc;
}

sub forget_dead_hosts { $memc->forget_dead_hosts(); }
sub disconnect_all    { $memc->disconnect_all();    }

sub delete    { $memc->delete(@_);    }
sub add       { $memc->add(@_);       }
sub replace   { $memc->replace(@_);   }
sub set       { $memc->set(@_);       }
sub get       { $memc->get(@_);       }
sub get_multi { $memc->get_multi(@_); }


1;
