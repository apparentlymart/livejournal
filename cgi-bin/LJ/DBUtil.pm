package LJ::DBUtil;

use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";

die "Don't use this in web context, it's only for admin scripts!"
    if LJ::is_web_context();

sub get_inactive_db {
    my $class   = shift;
    my $cid     = shift or die "no cid passed\n";
    my $verbose = shift;

    print STDERR " - cluster $cid... " if $verbose;

    # find approparite db server to connect to
    my $role = "cluster$cid";
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$cid}) {
        $role .= "b" if $ab eq 'a';
        $role .= "a" if $ab eq 'b';

        print STDERR "{active=$ab, using=$role}\n" if $verbose;
    } else {
        die "invalid cluster: $cid ?\n";
    }

    $LJ::DBIRole->clear_req_cache();
    my $db = LJ::get_dbh($role);
    if ($db) {
        $db->{RaiseError} = 1;
    }
    return $db;
}

sub validate_clusters {
    my $class = shift;

    foreach my $cid (@LJ::CLUSTERS) {
        unless (LJ::DBUtil->get_inactive_db($cid)) {
            print STDERR "   - found downed cluster: $cid (inactive side)\n";
            print STDERR "Aborted.  Please try again later.\n";
            exit 0;
        }
    }

    return 1;
}

## get cluster DB handler, preferred order: inactive DB, active DB
sub connect_to_cluster {
    my $class = shift;
    my $clid = shift;
    my $verbose = shift;
    
    my $dbr = ($LJ::IS_DEV_SERVER) ?
        LJ::get_cluster_reader($clid) : LJ::DBUtil->get_inactive_db($clid);
    unless ($dbr) {
        warn "Using master database for cluster #$clid"
            if $verbose;
        $dbr = LJ::get_cluster_reader($clid);
    }
    
    die "Can't get DB connection for cluster #$clid"
        unless $dbr;
    $dbr->{RaiseError} = 1;

    warn "Connected to cluster #$clid" if $verbose;

    return $dbr;
}

1;
