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

    print "-I- Cleaning commenturl.\n";
    $dbh->do("DELETE FROM commenturls WHERE timecreate < UNIX_TIMESTAMP() - 86400*30 LIMIT 50000");

    if ($LJ::COPPA_CHECK && $LJ::UNIQ_COOKIES) {
        print "-I- Cleaning underage uniqs.\n";
        $dbh->do("DELETE FROM underage WHERE timeof < (UNIX_TIMESTAMP() - 86400*90) LIMIT 2000");
    }

    print "-I- Cleaning friendstimes.\n";
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        $dbcm->do("DELETE FROM friendstimes WHERE added < UNIX_TIMESTAMP() - 86400*7 LIMIT 100000");
    }

    print "-I- Cleaning comet_history.\n";
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        $dbcm->do("DELETE FROM comet_history WHERE added < UNIX_TIMESTAMP() - 86400*10 LIMIT 100000");
    }

    print "-I- Cleaning captcha sessions.\n";
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        $dbcm->do("DELETE FROM captcha_session WHERE sesstime < UNIX_TIMESTAMP()-86400");
    }

    print "-I- Cleaning blobcache.\n";
    $dbh->do("DELETE FROM blobcache WHERE dateupdate < NOW() - INTERVAL 30 DAY");

    print "-I- Cleaning old anonymous comment IP logs.\n";
    my $count;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 432,000 seconds is 5 days
        $count += $dbcm->do('DELETE FROM tempanonips WHERE reporttime < (UNIX_TIMESTAMP() - 432000)');
    }
    print "    deleted $count\n";

    print "-I- Cleaning old random users.\n";
    my $count;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;

        my $secs = $LJ::RANDOM_USER_PERIOD * 24 * 60 * 60;
        while (my $deleted = $dbcm->do("DELETE FROM random_user_set WHERE posttime < (UNIX_TIMESTAMP() - $secs) LIMIT 1000")) {
            $count += $deleted;

            last if $deleted != 1000;
            sleep 10;
        }
    }
    print "    deleted $count\n";

    print "-I- Cleaning diresearchres.\n";
    # need insert before delete so master logs delete and slaves actually do it
    $dbh->do("INSERT INTO dirsearchres2 VALUES (MD5(NOW()), DATE_SUB(NOW(), INTERVAL 31 MINUTE), '')");
    $dbh->do("DELETE FROM dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");

    # clean incoming emails older than 7 days from Mogile...
    my $mogc = LJ::mogclient();
    if ($mogc) {
        print "-I- Cleaning incoming email temporary handles.\n";
        $sth = $dbh->prepare("SELECT ieid FROM incoming_email_handle WHERE timerecv < UNIX_TIMESTAMP() - 86400*7 LIMIT 10000");
        $sth->execute;
        while (my ($id) = $sth->fetchrow_array) {
            if ($mogc->delete("ie:$id")) {
                $dbh->do("DELETE FROM incoming_email_handle WHERE ieid=?", undef, $id);
            }
        }
    }

    print "-I- Cleaning meme.\n";
    do {
        $sth = $dbh->prepare("DELETE FROM meme WHERE ts < DATE_SUB(NOW(), INTERVAL 7 DAY) LIMIT 250");
        $sth->execute;
        if ($dbh->err) { print $dbh->errstr; }
        print "    deleted ", $sth->rows, "\n";
    } while ($sth->rows && ! $sth->err);

    print "-I- Cleaning old pending comments.\n";
    $count = 0;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 3600 seconds is one hour
        my $time = time() - 3600;
        $count += $dbcm->do('DELETE FROM pendcomments WHERE datesubmit < ? LIMIT 2000', undef, $time);
    }
    print "    deleted $count\n";

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

    # removing old posts from landing page
    print "-I- Removing old posts from landing page.\n";

    my $cats = $dbh->selectall_arrayref ("SELECT catid FROM category WHERE vert_id > 0", { Slice => {} });
    my $for_in = join ",", map { $_->{catid} } @$cats;
    my $comms = $for_in ? $dbh->selectall_arrayref ("SELECT journalid FROM categoryjournals WHERE catid IN($for_in)", { Slice => {} }) : [];
    my $cnt_delete = 0;
    foreach my $comm (@$comms) {
        my $posts = $dbh->selectall_arrayref ("SELECT jitemid FROM category_recent_posts WHERE journalid = ? ORDER BY timecreate ASC", { Slice => {} }, $comm->{'journalid'});
        splice @$posts, 0, 30;
        $cnt_delete += @#{$posts};
        my $in_to_delete = join ',', map { $_->{jitemid} } @$posts;
        $dbh->do ("DELETE FROM category_recent_posts WHERE journalid = ? AND jitemid IN ($in_to_delete)", undef, $comm->{'journalid'})
            if $in_to_delete;
    }
    print "    deleted $cnt_delete\n";

    LJ::run_hooks('extra_cache_clean');
};

1;
