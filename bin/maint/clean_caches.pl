#!/usr/bin/perl
#

$maint{'clean_caches'} = sub 
{
    my $dbh = LJ::get_db_writer();
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;

    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning faquses.\n";
    $dbh->do("DELETE FROM faquses WHERE dateview < DATE_SUB(NOW(), INTERVAL 7 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");

    print "-I- Cleaning captcha sessions.\n";
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        $dbcm->do("DELETE FROM captcha_session WHERE sesstime < UNIX_TIMESTAMP()-86400");
    }

    print "-I- Cleaning diresearchres.\n";
    # need insert before delete so master logs delete and slaves actually do it
    $dbh->do("INSERT INTO dirsearchres2 VALUES (MD5(NOW()), DATE_SUB(NOW(), INTERVAL 31 MINUTE), '')");
    $dbh->do("DELETE FROM dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");

    print "-I- Cleaning meme.\n";
    do {
        $sth = $dbh->prepare("DELETE FROM meme WHERE ts < DATE_SUB(NOW(), INTERVAL 7 DAY) LIMIT 250");
        $sth->execute;
        if ($dbh->err) { print $dbh->errstr; }
        print "    deleted ", $sth->rows, "\n";
    } while ($sth->rows && ! $sth->err);

    # move rows from talkleft_xfp to talkleft
    print "-I- Moving talkleft_xfp.\n";

    my $xfp_count = $dbh->selectrow_array("SELECT COUNT(*) FROM talkleft_xfp");
    print "    rows found: $xfp_count\n";

    if ($xfp_count) {

        my @xfp_cols = qw(userid posttime journalid nodetype nodeid jtalkid publicitem);
        my $xfp_cols = join(",", @xfp_cols);
        my $xfp_cols_join = join(",", map { "t.$_" } @xfp_cols);

        my %insert_vals;
        my %delete_vals;
        
        # select out 1000 rows from random clusters
        $sth = $dbh->prepare("SELECT u.clusterid,u.user,$xfp_cols_join " .
                             "FROM talkleft_xfp t, user u " .
                             "WHERE t.userid=u.userid LIMIT 1000");
        $sth->execute();
        my $row_ct = 0;
        while (my $row = $sth->fetchrow_hashref) {

            my %qrow = map { $_, $dbh->quote($row->{$_}) } @xfp_cols;

            push @{$insert_vals{$row->{'clusterid'}}},
                   ("(" . join(",", map { $qrow{$_} } @xfp_cols) . ")");
            push @{$delete_vals{$row->{'clusterid'}}},
                   ("(userid=$qrow{'userid'} AND " .
                    "journalid=$qrow{'journalid'} AND " .
                    "nodetype=$qrow{'nodetype'} AND " .
                    "nodeid=$qrow{'nodeid'} AND " .
                    "posttime=$qrow{'posttime'} AND " .
                    "jtalkid=$qrow{'jtalkid'})");

            $row_ct++;
        }

        foreach my $clusterid (sort keys %insert_vals) {
            my $dbcm = LJ::get_cluster_master($clusterid);
            unless ($dbcm) {
                print "    cluster down: $clusterid\n";
                next;
            }

            print "    cluster $clusterid: " . scalar(@{$insert_vals{$clusterid}}) .
                  " rows\n" if $verbose;
            $dbcm->do("INSERT INTO talkleft ($xfp_cols) VALUES " .
                      join(",", @{$insert_vals{$clusterid}})) . "\n";
            if ($dbcm->err) {
                print "    db error (insert): " . $dbcm->errstr . "\n";
                next;
            }

            # no error, delete from _xfp
            $dbh->do("DELETE FROM talkleft_xfp WHERE " .
                     join(" OR ", @{$delete_vals{$clusterid}})) . "\n";
            if ($dbh->err) {
                print "    db error (delete): " . $dbh->errstr . "\n";
                next;
            }
        }

        print "    rows remaining: " . ($xfp_count - $row_ct) . "\n";
    }

};

1;
