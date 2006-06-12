#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";

require "statslib.pl";

$maint{comm_promo_list} = sub
{
    my $verbose = $LJ::LJMAINT_VERBOSE >= 2 ? 1 : 0;

    # block size is 1_000 except for testing
    my $BLOCK_SIZE = $LJ::T_BLOCK_SIZE || 1_000;

    my $get_dbslo = sub {
        $LJ::DBIRole->clear_req_cache();
        return LJ::get_dbh("slow")
            or die "could not contact slow role";
    };

    my $dbslo = $get_dbslo->();

    # first get a list of all communities
    my @comm_uids = @{ $dbslo->selectcol_arrayref("SELECT userid FROM community") || [] };

    # go through each group of 1000 communities and find the total number
    # of watchers
    my $ct = 0;
    my $total_watchers = 0;
    my %promo_comms = (); # hash of jid => member count
    my @to_load = ();    # array of jids for which friends should be loaded

    while (my @curr_uid = splice(@comm_uids, 0, $BLOCK_SIZE)) {
        print "[" . ++$ct . "] processing " . scalar(@curr_uid) . " users...\n" if $verbose;

        # get u objects
        my $curr_u = LJ::load_userids(@curr_uid) || {};

        # how many of these communities are plus or paid w/ opt-in?
        while (my ($uid, $u) = each %$curr_u) {
            next unless $u->is_comm;
            next unless $u->{statusvis} eq 'V';

            # we care about users who are either sponsored plus or paid and have
            # opted in
            next unless $u->should_promote_comm;

            push @to_load, $u->{userid};
        }
    }

    # now iterate over all the users whose friend counts we'd like to load,
    # querying the slow role
    while (my @curr_uid = splice(@to_load, 0, $BLOCK_SIZE)) {
        $dbslo = $get_dbslo->();

        my $bind = join(",", map { "?" } @curr_uid);
        my $sth = $dbslo->prepare("SELECT friendid, COUNT(userid) FROM friends WHERE friendid IN ($bind) GROUP BY 1");
        $sth->execute(@curr_uid);
        die $dbslo->errstr if $dbslo->err;
        $sth->{mysql_use_result} = 1;

        while (my ($comm_id, $watcher_ct) = $sth->fetchrow_array) {
            $promo_comms{$comm_id} += $watcher_ct;
            $total_watchers += $watcher_ct;
        }
    }

    # no div by zero
    die "no community watchers found..."
        unless $total_watchers > 0;

    # now find what range in the table each community takes up
    my $curr_pos = 0;
    my @vals = ();
    my $max_int = $LJ::MAX_32BIT_SIGNED;
    while ( my ($jid, $watcher_ct) = each %promo_comms ) {
        my $weight = POSIX::ceil($watcher_ct / $total_watchers * $max_int);

        push @vals, ($jid, $curr_pos, $curr_pos + $weight);
        $curr_pos += $weight + 1;
    }

    # now insert all values in batch
    if (scalar @vals) {

        my $dbh = LJ::get_db_writer()
            or die "unable to contact global master";

        $dbh->begin_work;
        $dbh->do("DELETE FROM comm_promo_list");


        my $bind = join(",", map { "(?,?,?)" } keys %promo_comms);
        $dbh->do("INSERT INTO comm_promo_list (journalid, r_start, r_end) VALUES $bind", undef, @vals);
        $dbh->commit;
    }
};

1;
