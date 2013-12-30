#!/usr/bin/perl
#

my $display_time = sub {
        my ($what) = @_;

        if ( $what > 86400 ) {
            return sprintf( '%0.02f days', $what / 86400 );
        } elsif ( $what > 3600 ) {
            return sprintf( '%0.02f hr', $what / 3600 );
        } elsif ( $what > 60 ) {
            return sprintf( '%0.02f min', $what / 60 );
        } elsif ( $what > 1 ) {
            return sprintf( '%0.02f sec', $what );
        } else {
            return sprintf( '%0.02f msec', $what * 1000 );
        }
    };


$maint{'clean_caches'} = sub
{
    my $dbh = LJ::get_db_writer();
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;
    my ($count, $time);

    print "-I- Cleaning authactions.\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning faquses.\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM faquses WHERE dateview < DATE_SUB(NOW(), INTERVAL 7 DAY)");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning duplock.\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning commenturlsext.\n";
    $time = Time::HiRes::time();
    my $try1 = 0;
    while ($count = $dbh->do("DELETE FROM commenturlsext WHERE timecreate < UNIX_TIMESTAMP() - 86400*30 LIMIT 5000")) {
        print "    deleted $count, in ".$display_time->(Time::HiRes::time() - $time)."\n";
        last if $count < 5000 || ++$try1 >= 10;
        sleep 2;
        $time = Time::HiRes::time();
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";
    
    print "-I- Cleaning entry url.\n";
    $time = Time::HiRes::time();
    my $try2 = 0;
    while ($count = $dbh->do("DELETE FROM entryurlsext WHERE timecreate < UNIX_TIMESTAMP() - 86400*3 LIMIT 5000")) {
        print "    deleted $count, in ".$display_time->(Time::HiRes::time() - $time)."\n";
        last if $count < 5000 || ++$try2 >= 10;
        sleep 2;
        $time = Time::HiRes::time();
    }

    print "-I- Cleaning syslog table.\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM syslog WHERE log_time < UNIX_TIMESTAMP() - 86400 * 30 * 2");  ## 2 months
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    if ($LJ::COPPA_CHECK && $LJ::UNIQ_COOKIES) {
        print "-I- Cleaning underage uniqs.\n";
        $time = Time::HiRes::time();
        $count = $dbh->do("DELETE FROM underage WHERE timeof < (UNIX_TIMESTAMP() - 86400*90) LIMIT 2000");
        $time = Time::HiRes::time() - $time;
        print "    deleted $count, in ".$display_time->($time)."\n";
    }

    print "-I- Cleaning captcha sessions.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        $count += $dbcm->do("DELETE FROM captcha_session WHERE sesstime < UNIX_TIMESTAMP()-86400");
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted total $count in ".$display_time->($time)."\n";

    print "-I- Cleaning blobcache.\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM blobcache WHERE dateupdate < NOW() - INTERVAL 30 DAY");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";


    print "-I- Cleaning old anonymous comment IP logs.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 432,000 seconds is 5 days
        $count += $dbcm->do('DELETE FROM tempanonips WHERE reporttime < (UNIX_TIMESTAMP() - 432000)');
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning old random users.\n";
    $count = 0;
    $time = Time::HiRes::time();
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
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning diresearchres.\n";
    $time = Time::HiRes::time();
    # need insert before delete so master logs delete and slaves actually do it
    $dbh->do("INSERT INTO dirsearchres2 VALUES (MD5(NOW()), DATE_SUB(NOW(), INTERVAL 31 MINUTE), '')");
    $count = $dbh->do("DELETE FROM dirsearchres2 WHERE dateins < DATE_SUB(NOW(), INTERVAL 30 MINUTE)");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    # clean incoming emails older than 7 days from Mogile...
    my $mogc = LJ::mogclient();
    if ($mogc) {
        $count = 0;
        print "-I- Cleaning incoming email temporary handles.\n";
        $time = Time::HiRes::time();
        $sth = $dbh->prepare("SELECT ieid FROM incoming_email_handle WHERE timerecv < UNIX_TIMESTAMP() - 86400*7 LIMIT 10000");
        $sth->execute;
        while (my ($id) = $sth->fetchrow_array) {
            if ($mogc->delete("ie:$id")) {
                $count += $dbh->do("DELETE FROM incoming_email_handle WHERE ieid=?", undef, $id);
            }
        }
        $time = Time::HiRes::time() - $time;
        print "    deleted $count, in ".$display_time->($time)."\n";
    }

    print "-I- Cleaning meme.\n";
    do {
        $time = Time::HiRes::time();
        $sth = $dbh->prepare("DELETE FROM meme WHERE ts < DATE_SUB(NOW(), INTERVAL 7 DAY) LIMIT 250");
        $sth->execute;
        if ($dbh->err) { print $dbh->errstr; }
        $time = Time::HiRes::time() - $time;
        print "    deleted ", $sth->rows, ", in ".$display_time->($time)."\n";
    } while ($sth->rows && ! $sth->err);

    print "-I- Cleaning old pending comments.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 3600 seconds is one hour
        my $time = time() - 3600;
        $count += $dbcm->do('DELETE FROM pendcomments WHERE datesubmit < ? LIMIT 2000', undef, $time);
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    # move rows from talkleft_xfp to talkleft
    print "-I- Moving talkleft_xfp.\n";

    $time = Time::HiRes::time();
    my $xfp_count = $dbh->selectrow_array("SELECT COUNT(*) FROM talkleft_xfp");
    $time = Time::HiRes::time() - $time;
    print "    rows found: $xfp_count, in ".$display_time->($time)."\n";

    if ($xfp_count) {

        $time = Time::HiRes::time();
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
        $time = Time::HiRes::time() - $time;
        print "    rows remaining: " . ($xfp_count - $row_ct) . ", in ".$display_time->($time)."\n";
    }

    # removing old posts from landing page
    print "-I- Removing old posts from landing page.\n";

    $time = Time::HiRes::time();
    my $cats = $dbh->selectall_arrayref ("SELECT catid FROM category WHERE vert_id > 0", { Slice => {} });
    my $for_in = join ",", map { $_->{catid} } @$cats;
    my $comms = $for_in ? $dbh->selectall_arrayref ("SELECT journalid FROM categoryjournals WHERE catid IN($for_in)", { Slice => {} }) : [];
    my $cnt_delete = 0;
    foreach my $comm (@$comms) {
        my $posts = $dbh->selectall_arrayref ("SELECT jitemid FROM category_recent_posts WHERE journalid = ? ORDER BY timecreate DESC", { Slice => {} }, $comm->{'journalid'});
        splice @$posts, 0, 30;
        $cnt_delete += @#{$posts};
        my $in_to_delete = join ',', map { $_->{jitemid} } @$posts;
        $dbh->do ("DELETE FROM category_recent_posts WHERE journalid = ? AND jitemid IN ($in_to_delete)", undef, $comm->{'journalid'})
            if $in_to_delete;
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $cnt_delete, in ".$display_time->($time)."\n";

=head
    print "-I- Cleanup old unused rating records for homepage\n";
    use LJ::HomePage::Category;
    my $count = LJ::HomePage::Category->clear_unused_processed_items ();
    print "    deleted $count records\n\n";
=cut

    print "-I- Cleaning cc_usage\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM cc_usage WHERE time < (UNIX_TIMESTAMP() - 86400*30) LIMIT 5000");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Cleaning cc_lock\n";
    $time = Time::HiRes::time();
    $count = $dbh->do("DELETE FROM cc_lock WHERE locktill < UNIX_TIMESTAMP()");
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    print "-I- Remove outdated sessions.\n";
   # LJ::disconnect_dbs();
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbh = LJ::get_cluster_master($c);
        $count += $dbh->do("DELETE FROM sessions WHERE timeexpire < UNIX_TIMESTAMP() LIMIT 100000");
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";

    LJ::run_hooks('extra_cache_clean');
  #  LJ::disconnect_dbs();

    print "-I- Cleaning friendstimes.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        $count = $dbcm->do("DELETE FROM friendstimes WHERE added < UNIX_TIMESTAMP() - 86400*14 LIMIT 100000");
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";
  #  LJ::disconnect_dbs();

    print "-I- Cleaning comet_history.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        $count = $dbcm->do("DELETE FROM comet_history WHERE added < FROM_UNIXTIME( UNIX_TIMESTAMP() - 86400*10 ) LIMIT 100000");
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";
  #  LJ::disconnect_dbs();

    if (LJ::is_enabled('new_friends_and_subscriptions')) {
    print "-I- Cleaning invite tables.\n";
    $count = 0;
    $time = Time::HiRes::time();
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        $count += $dbcm->do("DELETE FROM invitesent WHERE recvtime < ( UNIX_TIMESTAMP() - 86400*30 ) LIMIT 100000");
        $count += $dbcm->do("DELETE FROM inviterecv WHERE recvtime < ( UNIX_TIMESTAMP() - 86400*30 ) LIMIT 100000");
    }
    $time = Time::HiRes::time() - $time;
    print "    deleted $count, in ".$display_time->($time)."\n";
 #   LJ::disconnect_dbs();
    }

};

1;
