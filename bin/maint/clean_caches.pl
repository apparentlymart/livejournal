#!/usr/bin/perl
#

$maint{'clean_caches'} = sub 
{
    my $dbh = LJ::get_dbh("master");
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;

    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning faquses.\n";
    $dbh->do("DELETE FROM faquses WHERE dateview < DATE_SUB(NOW(), INTERVAL 7 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");

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

    my $user_ct = 0;
    my %cluster_down;
    $sth = $dbh->prepare("SELECT DISTINCT u.clusterid, u.userid, u.user " .
                         "FROM user u, talkleft_xfp t " .
                         "WHERE u.userid=t.userid LIMIT 100");
    $sth->execute;
    while (my ($clusterid, $userid, $user) = $sth->fetchrow_array) {
        next if $cluster_down{$clusterid};
        
        my $dbcm = LJ::get_cluster_master($clusterid);
        unless ($dbcm) {
            print "    cluster down: $clusterid\n";
            $cluster_down{$clusterid} = 1;
            next;
        }

        # cluster is up, do move
        my $cols = join(",", qw(userid posttime journalid nodetype
                                nodeid jtalkid publicitem));

        $sth = $dbh->prepare("SELECT $cols FROM talkleft_xfp WHERE userid=?");
        $sth->execute($userid);
        my @insert_vals;
        while (my @curr_vals = $sth->fetchrow_array) {
            push @insert_vals, ("(" . 
                                join(",", map { $dbcm->quote($_) } @curr_vals) .
                                ")");
        }

        print "    moving: $user\n" if $verbose;
        $dbcm->do("INSERT INTO talkleft ($cols) VALUES " . join(",", @insert_vals));
        if ($dbcm->err) {
            print "    db error: " . $dbcm->errstr . "\n";
            next;
        }

        # no error, delete from _xfp
        $dbh->do("DELETE FROM talkleft_xfp WHERE userid=?", undef, $userid);

        $user_ct++;
    }
    print "    transferred $user_ct\n";
};

1;
