#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
use DBI::Role;
use DBI;

require "$ENV{LJHOME}/cgi-bin/ljconfig.pl";

$LJ::DBIRole = new DBI::Role {
    'timeout' => sub {
        my ($dsn, $user, $pass, $role) = @_;
        return 0 if $role eq "master";
        return $LJ::DB_TIMEOUT;
    },
    'sources' => \%LJ::DBINFO,
    'default_db' => "livejournal",
    'time_check' => 60,
    'time_report' => \&LJ::dbtime_callback,
};

package LJ::DB;

sub dbh_by_role {
    return $LJ::DBIRole->get_dbh( @_ );
}

sub dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'\n";

    my $fdsn = $dbh->selectrow_array("SELECT fdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No fdsn found for db name '$name'\n" unless $fdsn;

    return $LJ::DBIRole->get_dbh_conn($fdsn);

}

sub dbh_by_fdsn {
    my $fdsn = shift;
    return $LJ::DBIRole->get_dbh_conn($fdsn);
}

sub root_dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'";

    my $fdsn = $dbh->selectrow_array("SELECT rootfdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No rootfdsn found for db name '$name'\n" unless $fdsn;

    return $LJ::DBIRole->get_dbh_conn($fdsn);
}

package LJ;

sub no_cache {
    my $sb = shift;
    local $LJ::MemCache::GET_DISABLED = 1;
    return $sb->();
}

sub cond_no_cache {
    my ($cond, $sb) = @_;
    return no_cache($sb) if $cond;
    return $sb->();
}

# <LJFUNC>
# name: LJ::get_dbh
# class: db
# des: Given one or more roles, returns a database handle.
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_dbh {
    my $opts = ref $_[0] eq "HASH" ? shift : {};

    unless (exists $opts->{'max_repl_lag'}) {
        # for slave or cluster<n>slave roles, don't allow lag
        if ($_[0] =~ /slave$/) {
            $opts->{'max_repl_lag'} = $LJ::MAX_REPL_LAG || 100_000;
        }
    }

    if ($LJ::DEBUG{'get_dbh'} && $_[0] ne "logs") {
        my $errmsg = "get_dbh(@_) at \n";
        my $i = 0;
        while (my ($p, $f, $l) = caller($i++)) {
            next if $i > 3;
            $errmsg .= "  $p, $f, $l\n";
        }
        warn $errmsg;
    }

    my $nodb = sub {
        my $roles = shift;
        my $err = LJ::errobj("Database::Unavailable",
                             roles => $roles);
        return $err->cond_throw;
    };

    foreach my $role (@_) {
        # let site admin turn off global master write access during
        # maintenance
        return $nodb->([@_]) if $LJ::DISABLE_MASTER && $role eq "master";
        my $db = LJ::get_dbirole_dbh($opts, $role);
        return $db if $db;
    }
    return $nodb->([@_]);
}

sub get_db_reader {
    return LJ::get_dbh("slave", "master");
}

sub get_db_writer {
    return LJ::get_dbh("master");
}

# <LJFUNC>
# name: LJ::get_cluster_reader
# class: db
# des: Returns a cluster slave for a user, or cluster master if no slaves exist.
# args: uarg
# des-uarg: Either a userid scalar or a user object.
# returns: DB handle.  Or undef if all dbs are unavailable.
# </LJFUNC>
sub get_cluster_reader
{
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    my @roles = ("cluster${id}slave", "cluster${id}");
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$id}) {
        $ab = lc($ab);
        # master-master cluster
        @roles = ("cluster${id}${ab}") if $ab eq "a" || $ab eq "b";
    }
    return LJ::get_dbh(@roles);
}

# <LJFUNC>
# name: LJ::get_cluster_def_reader
# class: db
# des: Returns a definitive cluster reader for a given user, used
#      when the caller wants the master handle, but will only
#      use it to read.
# args: uarg
# des-uarg: Either a clusterid scalar or a user object.
# returns: DB handle.  Or undef if definitive reader is unavailable.
# </LJFUNC>
sub get_cluster_def_reader
{
    my @dbh_opts = scalar(@_) == 2 ? (shift @_) : ();
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    return LJ::get_cluster_reader(@dbh_opts, $id) if
        $LJ::DEF_READER_ACTUALLY_SLAVE{$id};
    return LJ::get_dbh(@dbh_opts, LJ::master_role($id));
}

# <LJFUNC>
# name: LJ::get_cluster_master
# class: db
# des: Returns a cluster master for a given user, used when the caller
#      might use it to do a write (insert/delete/update/etc...)
# args: uarg
# des-uarg: Either a clusterid scalar or a user object.
# returns: DB handle.  Or undef if master is unavailable.
# </LJFUNC>
sub get_cluster_master
{
    my @dbh_opts = scalar(@_) == 2 ? (shift @_) : ();
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    return undef if $LJ::READONLY_CLUSTER{$id};
    return LJ::get_dbh(@dbh_opts, LJ::master_role($id));
}

# returns the DBI::Role role name of a cluster master given a clusterid
sub master_role {
    my $id = shift;
    my $role = "cluster${id}";
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$id}) {
        $ab = lc($ab);
        # master-master cluster
        $role = "cluster${id}${ab}" if $ab eq "a" || $ab eq "b";
    }
    return $role;
}


# <LJFUNC>
# name: LJ::get_dbirole_dbh
# class: db
# des: Internal function for get_dbh(). Uses the DBIRole to fetch a dbh, with
#      hooks into db stats-generation if that's turned on.
# info:
# args: opts, role
# des-opts: A hashref of options.
# des-role: The database role.
# returns: A dbh.
# </LJFUNC>
sub get_dbirole_dbh {
    my $dbh = $LJ::DBIRole->get_dbh( @_ ) or return undef;

    if ( $LJ::DB_LOG_HOST && $LJ::HAVE_DBI_PROFILE ) {
        $LJ::DB_REPORT_HANDLES{ $dbh->{Name} } = $dbh;

        # :TODO: Explain magic number
        $dbh->{Profile} ||= "2/DBI::Profile";

        # And turn off useless (to us) on_destroy() reports, too.
        undef $DBI::Profile::ON_DESTROY_DUMP;
    }

    return $dbh;
}

# <LJFUNC>
# name: LJ::get_lock
# des: get a mysql lock on a given key/dbrole combination
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole, lockname, wait_time?
# des-dbrole: the role this lock should be gotten on, either 'global' or 'user'
# des-lockname: the name to be used for this lock
# des-wait_time: an optional timeout argument, defaults to 10 seconds
# </LJFUNC>
sub get_lock
{
    my ($db, $dbrole, $lockname, $wait_time) = @_;
    return undef unless $db && $lockname;
    return undef unless $dbrole eq 'global' || $dbrole eq 'user';

    my $curr_sub = (caller 1)[3]; # caller of current sub

    # die if somebody already has a lock
    die "LOCK ERROR: $curr_sub; can't get lock from: $LJ::LOCK_OUT{$dbrole}\n"
        if exists $LJ::LOCK_OUT{$dbrole};

    # get a lock from mysql
    $wait_time ||= 10;
    $db->do("SELECT GET_LOCK(?,?)", undef, $lockname, $wait_time)
        or return undef;

    # successfully got a lock
    $LJ::LOCK_OUT{$dbrole} = $curr_sub;
    return 1;
}

# <LJFUNC>
# name: LJ::may_lock
# des: see if we COULD get a mysql lock on a given key/dbrole combination,
#      but don't actually get it.
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole
# des-dbrole: the role this lock should be gotten on, either 'global' or 'user'
# </LJFUNC>
sub may_lock
{
    my ($db, $dbrole) = @_;
    return undef unless $db && ($dbrole eq 'global' || $dbrole eq 'user');

    # die if somebody already has a lock
    if ($LJ::LOCK_OUT{$dbrole}) {
        my $curr_sub = (caller 1)[3]; # caller of current sub
        die "LOCK ERROR: $curr_sub; can't get lock from $LJ::LOCK_OUT{$dbrole}\n";
    }

    # see if a lock is already out
    return undef if exists $LJ::LOCK_OUT{$dbrole};

    return 1;
}

# <LJFUNC>
# name: LJ::release_lock
# des: release a mysql lock on a given key/dbrole combination
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole, lockname
# des-dbrole: the role this lock should be gotten on, either 'global' or 'user'
# des-lockname: the name to be used for this lock
# </LJFUNC>
sub release_lock
{
    my ($db, $dbrole, $lockname) = @_;
    return undef unless $db && $lockname;
    return undef unless $dbrole eq 'global' || $dbrole eq 'user';

    # get a lock from mysql
    $db->do("SELECT RELEASE_LOCK(?)", undef, $lockname);
    delete $LJ::LOCK_OUT{$dbrole};

    return 1;
}

# <LJFUNC>
# name: LJ::disconnect_dbs
# des: Clear cached DB handles and trackers/keepers to partitioned DBs.
# </LJFUNC>
sub disconnect_dbs {
    # clear cached handles
    $LJ::DBIRole->disconnect_all( { except => [qw(logs)] });

    # and cached trackers/keepers to partitioned dbs
    while (my ($role, $tk) = each %LJ::REQ_DBIX_TRACKER) {
        $tk->disconnect if $tk;
    }
    %LJ::REQ_DBIX_TRACKER = ();
    %LJ::REQ_DBIX_KEEPER = ();
}

# given two db roles, returns true only if the two roles are for sure
# served by different database servers.  this is useful for, say,
# the moveusercluster script:  you wouldn't want to select something
# from one db, copy it into another, and then delete it from the
# source if they were both the same machine.
# <LJFUNC>
# name: LJ::use_diff_db
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub use_diff_db {
    $LJ::DBIRole->use_diff_db(@_);
}

# to be called as &nodb; (so this function sees caller's @_)
sub nodb {
    shift @_ if
        ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db" ||
        ref $_[0] eq "DBIx::StateKeeper" || ref $_[0] eq "Apache::DBI::db";
}

sub dbtime_callback {
    my ($dsn, $dbtime, $time) = @_;
    my $diff = abs($dbtime - $time);
    if ($diff > 2) {
        $dsn =~ /host=([^:\;\|]*)/;
        my $db = $1;
        print STDERR "Clock skew of $diff seconds between web($LJ::SERVER_NAME) and db($db)\n";
    }
}


sub isdb { return ref $_[0] && (ref $_[0] eq "DBI::db" ||
                                ref $_[0] eq "DBIx::StateKeeper" ||
                                ref $_[0] eq "Apache::DBI::db"); }


package LJ::Error::Database::Unavailable;
sub fields { qw(roles) }  # arrayref of roles requested

sub as_string {
    my $self = shift;
    my $ct = @{$self->field('roles')};
    my $clist = join(", ", @{$self->field('roles')});
    return $ct == 1 ?
        "Database unavailable for role $clist" :
        "Database unavailable for roles $clist";
}


package LJ::Error::Database::Failure;
sub fields { qw(db) }

sub as_string {
    my $self = shift;
    my $code = $self->err;
    my $txt  = $self->errstr;
    return "Database error code $code: $txt";
}

sub err {
    my $self = shift;
    return $self->field('db')->err;
}

sub errstr {
    my $self = shift;
    return $self->field('db')->errstr;
}

1;
