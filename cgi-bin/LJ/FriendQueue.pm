package LJ::FriendQueue;

use strict;
use warnings;

# Internal modules
use LJ::MemCache;

## This module is an interface to queue with addfriend/delfriend user activities.
## It's used to delay notification of the addfriend/delfriend event and 
## send all events simultaneously.

sub push {
    my ($class, $u, $target, %opts) = @_;
    die 'Expected parameter $u in push' unless $u;
    die 'Expected parameter $target in push' unless $target;

    my $etime  = $opts{etime};
    my $jobid  = $opts{jobid};
    my $action = $opts{action};

    $etime ||= time();

    if ($action eq 'add') {
        $action = 'A';
    } elsif ($action eq 'del') {
        $action = 'D';
    } elsif ($action eq 'invite') {
        $action = 'I';
    } else {
        $action = '';
    }

    return unless $action;

    my $uid = $u->id;
    my $tid = $target->id;

    return unless $uid;
    return unless $tid;

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;
    
    ## update storage
    $dbh->do(qq[
            INSERT INTO friending_actions_q (
                userid, friendid, action, etime, jobid
            ) VALUES (
                ?, ?, ?, ?, ?
            )
        ],
        undef,
        $uid,
        $tid,
        $action,
        $etime,
        $jobid
    );

    if ($dbh->err) {
        return;
    }
    
    ## update cached value
    LJ::MemCache::incr([$uid, "friend_q_cnt:$uid"]);

    return 1;
}

sub load {
    my ($class, $u) = @_;
    die 'Expected parameter $u in load()' unless $u;

    my $uid = $u->id;

    return unless $uid;

    my $dbh = LJ::get_cluster_reader($u);

    return unless $dbh;

    my $rows = $dbh->selectall_arrayref(qq[
            SELECT
                *
            FROM
                friending_actions_q 
            WHERE
                userid = ?
            ORDER BY
                rec_id
        ],
        {
            Slice => {}
        },
        $uid
    );

    if ($dbh->err) {
        return;
    }

    return @$rows;
}

sub empty {
    my ($class, $u, $rec_id) = @_;
    die 'Expected parameter $u in empty()' unless $u;

    my $uid = $u->id;

    return unless $uid;

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    my $where = '';

    if ($rec_id) {
        $where = " AND rec_id <= " . int($rec_id);
    }

    $dbh->do(qq[
        DELETE 
            FROM friending_actions_q 
        WHERE 
            userid = ?
        $where
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }
    
    LJ::MemCache::delete([$uid, "friend_q_cnt:$uid"]);

    return 1;
}

sub count {
    my ($class, $u) = @_;
    die 'Expected parameter in count()' unless $u;

    my $uid = $u->id;

    return unless $uid;

    ## check cache
    my $key = [$uid, "friend_q_cnt:$uid"];
    my $val = LJ::MemCache::get($key);

    return $val if defined $val;

    my $dbh = LJ::get_cluster_reader($u);

    return unless $dbh;

    my ($count) = $dbh->selectrow_array(qq[
            SELECT
                COUNT(1) 
            FROM
                friending_actions_q
            WHERE
                userid = ?
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    ##
    LJ::MemCache::set($key, $count, 3600);

    return $count;
}

1;
