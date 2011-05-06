package LJ::User::PropStorage;
use strict;
use warnings;

use LJ::ModuleLoader;
use Carp qw();

# initialization code. do not touch this.
my @SUBCLASSES = LJ::ModuleLoader->module_subclasses(__PACKAGE__);
use LJ::User::PropStorage::DB;
foreach my $class (@SUBCLASSES) {
    eval "use $class";
    Carp::confess "Error loading module '$class': $@" if $@;
}

my %handlers_map;

sub get_handler {
    my ($class, $propname) = @_;

    return $handlers_map{$propname} if $handlers_map{$propname};

    foreach my $class (@SUBCLASSES) {
        next unless $class->can_handle($propname);
        return ( $handlers_map{$propname} = $class );
    }

    Carp::croak 'cannot get a handler for prop=' . $propname;
}

sub get_handler_multi {
    my ($class, $props) = @_;

    my %ret;

    foreach my $prop (@$props) {
        my $handler = $class->get_handler($prop);

        $ret{$handler} = [] unless exists $ret{$handler};
        push @{ $ret{$handler} }, $prop;
    }

    return \%ret;
}

sub get_props {
    my ( $class, $u, $props, $opts ) = @_;

    Carp::croak $class . 'does not have a "get" method defined';
}

sub set_props {
    my ( $class, $u, $propmap, $opts ) = @_;

    Carp::croak $class . 'does not have a "set" method defined';
}

sub can_handle {
    my ( $class, $propname ) = @_;

    Carp::croak $class . 'does not have a "can_handle" method defined';
}

sub use_memcache {
    my ($class) = @_;

    Carp::croak $class . 'does not have a "use_memcache" method defined';
}

sub memcache_key {
    my ( $class, $u, $propname ) = @_;

    Carp::croak $class . 'does not have a "memcache_key" method defined';
}

sub fetch_props_memcache {
    my ( $class, $u, $props ) = @_;

    my $userid = int $u->userid;

    my ( %propid_map, @memkeys );
    foreach my $k (@$props) {
        my $propinfo = LJ::get_prop('user', $k);
        my $propid   = $propinfo->{'id'};
        my $memkey   = $class->memcache_key($u, $k);

        $propid_map{$k} = $propid;
        push @memkeys, [ $userid, $memkey ];
    }

    my $from_memcache = LJ::MemCache::get_multi(@memkeys);

    my %ret;
    foreach my $k (@$props) {
        my $memkey = $class->memcache_key($u, $k);

        next unless exists $from_memcache->{$memkey};

        $ret{ $k } = $from_memcache->{$memkey};
    }

    return \%ret;
}

sub store_props_memcache {
    my ( $class, $u, $propmap ) = @_;

    my $userid = int $u->userid;
    my $expire = time + 3600 * 24;

    foreach my $k (keys %$propmap) {
        my $memkey = $class->memcache_key($u, $k);

        LJ::MemCache::set( [ $userid, $memkey ],
                           $propmap->{$k} || '',
                           $expire );
    }
}

sub pack_for_memcache {
    my ( $class, $propmap ) = @_;

    my %ret;
    foreach my $propname (keys %$propmap) {
        my $propinfo = LJ::get_prop( 'user', $propname );
        my $propid   = $propinfo->{'id'};

        $ret{$propid} = $propmap->{$propname};
    }

    return \%ret;
}

sub unpack_from_memcache {
    my ( $class, $packed ) = @_;

    my %ret;
    foreach my $propid (keys %$packed) {
        my $propname = $LJ::CACHE_PROPID{'user'}->{$propid}->{'name'};
        next unless defined $propname;
        $ret{$propname} = $packed->{$propid};
    }

    return \%ret;
}

1;
