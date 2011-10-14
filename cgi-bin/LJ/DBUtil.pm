package LJ::DBUtil;
use strict;

use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";

die "Don't use this in web context, it's only for admin scripts!"
    if LJ::is_web_context();

sub get_inactive_db {
    my $class   = shift;
    my $cid     = shift or die "no cid passed\n";
    my $verbose = shift;

    print STDERR " - cluster $cid... " if $verbose;

    my $role = LJ::get_inactive_role($cid);
    return unless $role;

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
    
    my $dbr = LJ::DBUtil->get_inactive_db($clid, $verbose);
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
