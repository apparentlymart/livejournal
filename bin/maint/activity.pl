#!/usr/bin/perl
#

use LJ::TimeUtil;

$maint{'active_user'} = sub
{
    my $dbh = LJ::get_db_writer();
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;

    # move clustered active_user stats from each cluster to the global active_user_summary table
    print "-I- Migrating active_user records.\n";
    $count = 0;
    foreach my $cid (@LJ::CLUSTERS) {
        next unless $cid;

        my $dbcm = LJ::get_cluster_master($cid);
        unless ($dbcm) {
            print "    cluster down: $clusterid\n";
            next;
        }

        unless ($dbcm->do("LOCK TABLES active_user WRITE")) {
            print "    db error (lock): " . $dbcm->errstr . "\n";
            next;
        }

        # We always want to keep at least an hour worth of data in the
        # clustered table for duplicate checking.  We won't select out
        # any rows for this hour or the full hour before in order to avoid
        # extra rows counted in hour-boundary edge cases
        my $now = time();

        # one hour from the start of this hour (
        my $before_time = $now - 3600 - ($now % 3600);
        my $time_str = LJ::TimeUtil->mysql_time($before_time, 'gmt');

        # now extract parts from the modified time
        my ($yr, $mo, $day, $hr) =
            $time_str =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)/;

        # Building up all this sql is pretty ghetto but otherwise it
        # becomes unwieldy with tons of code duplication and more places
        # for this fairly-complicated where condition to break.  So we'll
        # build a nice where clause which uses bind vars and then create
        # an array to go inline in the spot where those bind vars should
        # be within the larger query
        my $where = "WHERE year=? AND month=? AND day=? AND hour<? OR " .
                    "year=? AND month=? AND day<? OR " .
                    "year=? AND month<? OR " .
                    "year<?";

        my @where_vals = ($yr, $mo, $day, $hr,
                          $yr, $mo, $day,
                          $yr, $mo,
                          $yr                );

        # don't need to check for distinct userid in the count here
        # because y,m,d,h,uid is the primary key so we know it's
        # unique for this hour anyway
        my $sth = $dbcm->prepare
            ("SELECT type, year, month, day, hour, COUNT(userid) " .
             "FROM active_user $where GROUP BY 1,2,3,4,5");
        $sth->execute(@where_vals);

        if ($dbcm->err) {
            print "    db error (select): " . $dbcm->errstr . "\n";
            next;
        }

        my %counts = ();
        my $total_ct = 0;
        while (my ($type, $yr, $mo, $day, $hr, $ct) = $sth->fetchrow_array) {
            $counts{"$yr-$mo-$day-$hr-$type"} += $ct;
            $total_ct += $ct;
        }

        print "    cluster $cid: $total_ct rows\n" if $verbose;

        # Note: We can experience failures on both sides of this
        #       transaction.  Either our delete can succeed then
        #       insert fail or vice versa.  Luckily this data is
        #       for statistical purposes so we can just live with
        #       the possibility of a small skew.

        unless ($dbcm->do("DELETE FROM active_user $where", undef, @where_vals)) {
            print "    db error (delete): " . $dbcm->errstr . "\n";
            next;
        }

        # at this point if there is an error we will ignore it and try
        # to insert the count data above anyway
        my $rv = $dbcm->do("UNLOCK TABLES")
            or print "    db error (unlock): " . $dbcm->errstr . "\n";

        # nothing to insert, why bother?
        next unless %counts;

        # insert summary into active_user_summary table
        my @bind = ();
        my @vals = ();
        while (my ($hkey, $ct) = each %counts) {

            # yyyy, mm, dd, hh, cid, type, ct
            push @bind, "(?, ?, ?, ?, ?, ?, ?)";

            my ($yr, $mo, $day, $hr, $type) = split(/-/, $hkey);
            push @vals, ($yr, $mo, $day, $hr, $cid, $type, $ct);
        }
        my $bind = join(",", @bind);

        $dbh->do("INSERT IGNORE INTO active_user_summary (year, month, day, hour, clusterid, type, count) " .
                 "VALUES $bind", undef, @vals);

        if ($dbh->err) {
            print "    db error (insert): " . $dbh->errstr . "\n";

            # something's badly b0rked, don't try any other clusters for now
            last;
        }

        # next cluster
    }
};
# End active_user


$maint{'actionhistory'} = sub
{
    my $dbh = LJ::get_db_writer();
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;


    # move clustered recentaction summaries from their respective clusters
    # to the global actionhistory table
    print "-I- Migrating recentactions.\n";

    foreach my $cid (@LJ::CLUSTERS) {
        next unless $cid;

        my $dbcm = LJ::get_cluster_master($cid);
        unless ($dbcm) {
            print "    cluster down: $clusterid\n";
            next;
        }

        unless ($dbcm->do("LOCK TABLES recentactions WRITE")) {
            print "    db error (lock): " . $dbcm->errstr . "\n";
            next;
        }

        my $sth = $dbcm->prepare
            ("SELECT what, COUNT(*) FROM recentactions GROUP BY 1");
        $sth->execute;
        if ($dbcm->err) {
            print "    db error (select): " . $dbcm->errstr . "\n";
            next;
        }

        my %counts = ();
        my $total_ct = 0;
        while (my ($what, $ct) = $sth->fetchrow_array) {
            $counts{$what} += $ct;
            $total_ct += $ct;
        }

        print "    cluster $cid: $total_ct rows\n" if $verbose;

        # Note: We can experience failures on both sides of this
        #       transaction.  Either our delete can succeed then
        #       insert fail or vice versa.  Luckily this data is
        #       for statistical purposes so we can just live with
        #       the possibility of a small skew.

        unless ($dbcm->do("DELETE FROM recentactions")) {
            print "    db error (delete): " . $dbcm->errstr . "\n";
            next;
        }

        # at this point if there is an error we will ignore it and try
        # to insert the count data above anyway
        $dbcm->do("UNLOCK TABLES")
            or print "    db error (unlock): " . $dbcm->errstr . "\n";

        # nothing to insert, why bother?
        next unless %counts;

        # TEMPORARY
        # We want to move from using one letter, or prefixed with _ to
        # mean local, to actual readable strings.  Instead of fighting
        # a race when modifying the recentactions table, do it here instead.
        # This could should be removable after the code is pushed live and this
        # job has run.
        # David (1/11/06);
        my %whatmap = (
                       'P'             => 'post',
                       'post'          => 'post',
                       '_F'            => 'phonepost',
                       'phonepost'     => 'phonepost',
                       '_M'            => 'phonepost_mp3',
                       'phonepost_mp3' => 'phonepost_mp3',
                       );

        # insert summary into global actionhistory table
        my @bind = ();
        my @vals = ();
        while (my ($what, $ct) = each %counts) {
            push @bind, "(UNIX_TIMESTAMP(),?,?,?)";

            # TEMPORARY
            my $cwhat = defined $whatmap{$what} ? $whatmap{$what} : $what;

            push @vals, $cid, $cwhat, $ct;
        }
        my $bind = join(",", @bind);

        $dbh->do("INSERT INTO actionhistory (time, clusterid, what, count) " .
                 "VALUES $bind", undef, @vals);
        if ($dbh->err) {
            print "    db error (insert): " . $dbh->errstr . "\n";

            # something's badly b0rked, don't try any other clusters for now
            last;
        }

        # next cluster
    }
};

1;
