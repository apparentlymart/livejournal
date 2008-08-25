#!/usr/bin/perl
#
# Goes over every user, updating their dversion to 8 and
# migrating whatever polls they have to their user cluster

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Poll;
use Term::ReadLine;

my $BLOCK_SIZE = 10_000; # get users in blocks of 10,000
my $VERBOSE    = 0;      # print out extra info

my %handle;

# database handle retrieval sub
my $get_db_handles = sub {
    # figure out what cluster to load
    my $cid = shift(@_) + 0;

    my $dbh = $handle{0};
    unless ($dbh) {
        $dbh = $handle{0} = LJ::get_dbh({ raw => 1 }, "master");
        print "Connecting to master ($dbh)...\n";
        eval {
            $dbh->do("SET wait_timeout=28800");
        };
        $dbh->{'RaiseError'} = 1;
    }

    my $dbcm;
    $dbcm = $handle{$cid} if $cid;
    if ($cid && ! $dbcm) {
        $dbcm = $handle{$cid} = LJ::get_cluster_master({ raw => 1 }, $cid);
        print "Connecting to cluster $cid ($dbcm)...\n";
        return undef unless $dbcm;
        eval {
            $dbcm->do("SET wait_timeout=28800");
        };
        $dbcm->{'RaiseError'} = 1;
    }

    # return one or both, depending on what they wanted
    return $cid ? ($dbh, $dbcm) : $dbh;
};


my $dbh = LJ::get_db_writer()
    or die "Could not connect to global master";


my $term = new Term::ReadLine 'd7-d8 migrator';
my $line = $term->readline("Do you want to update to dversion 8 (clustered polls)? [N/y] ");
unless ($line =~ /^y/i) {
    print "Not upgrading to dversion 8\n\n";
    exit;
}

print "\n--- Upgrading users to dversion 8 (clustered polls) ---\n\n";

# Have the script end gracefully once a certain amount of time has passed
$line = $term->readline("After how many hours do you want the script to stop? [1-8] ");
unless ($line =~ /^[1-8]/) {
    print "Not a valid number. Choose a number between 1 and 8\n";
    exit;
}
my $endtime = time() + ($line * 3600);

# get user count
my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 7");
print "\tTotal users at dversion 7: $total\n\n";

my $migrated = 0;

foreach my $cid (@LJ::CLUSTERS) {
    # get a handle for every user to revalidate our connection?
    my ($mdbh, $udbh) = $get_db_handles->($cid)
        or die "Could not get cluster master handle for cluster $cid";

    while (time() < $endtime) {
        my $sth = $mdbh->prepare("SELECT userid FROM user WHERE dversion=7 AND clusterid=? LIMIT $BLOCK_SIZE");
        $sth->execute($cid);
        die $sth->errstr if $sth->err;

        my $count = $sth->rows;
        print "\tGot $count users on cluster $cid with dversion=7\n";
        last unless $count;

        while ((time() < $endtime) && (my ($userid) = $sth->fetchrow_array)) {
            my $u = LJ::load_userid($userid)
                or die "Invalid userid: $userid";

            # assign this dbcm to the user
            if ($udbh) {
                $u->set_dbcm($udbh)
                    or die "unable to set database for $u->{user}: dbcm=$udbh\n";
            }

            # lock while upgrading
            my $lock = LJ::locker()->trylock("d7d8-$userid");
            unless ($lock) {
                print STDERR "Could not get a lock for user " . $u->user . ".\n";
                next;
            }

            my $ok = eval { $u->upgrade_to_dversion_8($mdbh, $udbh) };
            $lock->release;

            die $@ if $@;

            print "\tMigrated user " . $u->user . "... " . ($ok ? 'ok' : 'ERROR') . "\n"
                if $VERBOSE;

            $migrated++ if $ok;
        }

        print "\t - Migrated $migrated users so far\n\n";

        # make sure we don't end up running forever for whatever reason
        last if $migrated > $total;
    }
}

print "--- Done migrating $migrated of $total users to dversion 8 ---\n";
