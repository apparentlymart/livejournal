# This class is used to keep track of a typeid => class name
# mapping in the database. You create a new typemap object and
# describe the table to it (tablename, class field name, id field name)
# You can then look up class->typeid or vice-versa on the Typemap object
# Mischa Spiegelmock, 4/21/06

use strict;
package LJ::Typemap;
use Carp qw/croak/;

*new = \&instance;

my %singletons = ();

# class method
# table is the typemap table
# the fields are the names of the fields in the table
sub instance {
    my ($class, %opts) = @_;

    my $table      = delete $opts{table}      or croak "No table";
    my $classfield = delete $opts{classfield} or croak "No class field";
    my $idfield    = delete $opts{idfield}    or croak "No id field";

    croak "Extra args passed to LJ::Typemap->new" if %opts;

    return $singletons{$table} if $singletons{$table};

    croak "Invalid arguments passed to LJ::Typemap->new"
        unless ($class && $table !~ /\W/g && $idfield !~/\W/g && $classfield !~/\W/g);

    my $self = {
        table      => $table,
        idfield    => $idfield,
        classfield => $classfield,
        loaded     => 0,
        cache      => {},
    };

    return $singletons{$table} = bless $self, $class;
}

# just what it says
# errors hard if you look up a typeid that isn't mapped
sub typeid_to_class {
    my ($self, $typeid) = @_;

    $self->_load unless $self->{loaded};
    my $proc_cache = $self->{cache};

    my ($class) = grep { $proc_cache->{$_} == $typeid } keys %$proc_cache;

    die "No class for id $typeid on table $self->{table}" unless $class;

    return $class;
}

# this will return the typeid of a given class.
# if there is no typeid for this class, it will create one.
# returns undef on failure
sub class_to_typeid {
    my ($self, $class) = @_;

    $self->_load unless $self->{loaded};
    my $proc_cache = $self->{cache};
    my $classid = $proc_cache->{$class};
    return $classid if defined $classid;

    # this class does not have a typeid. create one.
    my $dbh = LJ::get_db_writer();

    my $table = $self->{table} or die "No table";
    my $classfield = $self->{classfield} or die "No class field";
    my $idfield = $self->{idfield} or die "No id field";

    # try to insert
    $dbh->do("INSERT IGNORE INTO $table ($classfield) VALUES (?)",
             undef, $class);

    if ($dbh->{'mysql_insertid'}) {
        # inserted fine, get ID
        $classid = $dbh->{'mysql_insertid'};
    } else {
        # race condition, try to select again
        $classid = $dbh->selectrow_array("SELECT $idfield FROM $table WHERE $classfield = ?",
                                         undef, $class)
            or die "Typemap could not generate ID after race condition";
    }

    # we had better have a classid by now... big trouble if we don't
    die "Could not create typeid for table $table class $class" unless $classid;

    # save new classid
    $proc_cache->{$class} = $classid;

    $self->proc_cache_to_memcache;

    return $classid;
}

# save the process cache to memcache
sub proc_cache_to_memcache {
    my $self = shift;
    my $table = $self->{table};
    # memcache typeids
    LJ::MemCache::set("typemap_$table", $self->{cache}, 120);
}

# returns an array of all of the classes in the table
sub all_classes {
    my $self = shift;

    $self->_load;
    return keys %{$self->{cache}};
}

# makes sure typemap cache is loaded
sub _load {
    my $self = shift;

    $self->{loaded} = 1;

    my $table = $self->{table} or die "No table";
    my $classfield = $self->{classfield} or die "No class field";
    my $idfield = $self->{idfield} or die "No id field";

    my $proc_cache = $self->{cache};

    # is it memcached?
    my $memcached_typemap = LJ::MemCache::get("typemap_$table");
    if ($memcached_typemap) {
        # process-cache it
        $proc_cache = $memcached_typemap;
    }

    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    # load typemap from DB
    my $sth = $dbr->prepare("SELECT $classfield, $idfield FROM $table");
    return undef unless $sth;

    $sth->execute($idfield, $classfield, $table);

    while (my $idmap = $sth->fetchrow_hashref) {
        $proc_cache->{$idmap->{$classfield}} = $idmap->{$idfield};
    }

    # save in memcache
    $self->proc_cache_to_memcache;
}

1;
