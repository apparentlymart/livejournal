package LJ::Test;
require Exporter;
use Carp qw(croak);
@ISA = qw(Exporter);
@EXPORT = qw(memcache_stress with_fake_memcache temp_user);

my @temp_userids;  # to be destroyed later
END {
    # clean up temporary usernames
    foreach my $uid (@temp_userids) {
        my $u = LJ::load_userid($uid) or next;
        $u->delete_and_purge_completely;
    }
}

sub temp_user {
    my %args = @_;
    my $underscore  = delete $args{'underscore'};
    my $journaltype = delete $args{'journaltype'}  || "P";
    croak('unknown args') if %args;

    my $pfx = $underscore ? "_" : "t_";
    while (1) {
        my $username = $pfx . LJ::rand_chars(15 - length $pfx);
        my $uid = LJ::create_account({
            user => $username,
            name => "test account $username",
            email => "test\@$LJ::DOMAIN",
            journaltype => $journaltype,
        });
        if ($uid) {
            my $u = LJ::load_userid($uid) or next;
            push @temp_userids, $uid;
            return $u;
        }
    }
}

sub with_fake_memcache (&) {
    my $cb = shift;
    my $pre_mem = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::FakeMemCache->new();
    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}

sub memcache_stress (&) {
    my $cb = shift;
    my $pre_mem = LJ::MemCache::get_memcache();
    my $fake_memc = LJ::Test::FakeMemCache->new();

    # run the callback once with no memcache server existing
    {
        local @LJ::MEMCACHE_SERVERS = ();
        LJ::MemCache::init();
        $cb->();
    }

    # now set a memcache server, but a new empty one, and run it twice
    # so the second invocation presumably has stuff in the cache
    # from the first one
    {
        local @LJ::MEMCACHE_SERVERS = ("fake");
        LJ::MemCache::set_memcache($fake_memc);
        $cb->();
        $cb->();
    }

    # restore our memcache client object from before.
    LJ::MemCache::set_memcache($pre_mem);
}


package LJ::Test::FakeMemCache;
# duck-typing at its finest!
# this is a fake Cache::Memcached object which implements the
# memcached server locally in-process, for testing.  kinda,
# except it has no LRU or expiration times.

sub new {
    my ($class) = @_;
    return bless {
        'data' => {},
    }, $class;
}

sub add {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    return 0 if exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub replace {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    return 0 unless exists $self->{data}{$key};
    $self->{data}{$key} = $val;
    return 1;
}

sub set {
    my ($self, $fkey, $val, $exptime) = @_;
    my $key = _key($fkey);
    $self->{data}{$key} = $val;
    return 1;
}

sub delete {
    my ($self, $fkey) = @_;
    my $key = _key($fkey);
    delete $self->{data}{$key};
    return 1;
}

sub get {
    my ($self, $fkey) = @_;
    my $key = _key($fkey);
    return $self->{data}{$key};
}

sub get_multi {
    my $self = shift;
    my $ret = {};
    foreach my $fkey (@_) {
        my $key = _key($fkey);
        $ret->{$key} = $self->{data}{$key} if exists $self->{data}{$key};
    }
    return $ret;
}

sub _key {
    my $fkey = shift;
    return $fkey->[1] if ref $fkey eq "ARRAY";
    return $fkey;
}

# tell LJ::MemCache::reload_conf not to call 'weird' methods on us
# that we don't simulate.
sub doesnt_want_configuration {
    1;
}

sub disconnect_all {}
sub forget_dead_hosts {}


1;
