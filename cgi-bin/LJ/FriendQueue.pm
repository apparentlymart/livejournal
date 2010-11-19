package LJ::FriendQueue;
use strict;
use LJ::MemCache;
## This module is an interface to queue with addfriend/delfriend user activities.
## It's used to delay notification of the addfriend/delfriend event and 
## send all events simultaneously.

sub count {
    my $class    = shift;
    my $userid   = shift;

    ## check cache
    my $key = [$userid, "friend_q_cnt:$userid"];
    my $cache = LJ::MemCache::get($key);
    return $cache if $cache;

    my $u = LJ::load_userid($userid);
    my $dbcr = LJ::get_cluster_reader($u->clusterid);

    my ($count) = $dbcr->selectrow_array("
            SELECT count(1) 
            FROM friending_actions_q
            WHERE
                userid = ?
            ", undef, $u->userid)
        or warn "Can't select from friend_actions_q: " . DBI->errstr;

    ##
    LJ::MemCache::set($key, $count, 3600);

    return $count;
}


sub push {
    my $class = shift;
    my %opts = @_;
    my $userid   = $opts{userid};
    my $friendid = $opts{friendid};
    my $action   = $opts{action} eq 'add' ? 'A' : 'D';
    my $etime    = $opts{etime} || time();
    my $jobid    = $opts{jobid};

    my $u = LJ::load_userid($userid);
    my $dbcw = LJ::get_cluster_master($u->clusterid);
    
    ## update storage
    $dbcw->do("INSERT INTO friending_actions_q
                (userid, friendid, action, etime, jobid)
                VALUES
                (?,?,?,?,?)", undef,
                $userid, $friendid, $action, $etime, $jobid)
        or die "Can't insert into friend_actions_q: " . DBI->errstr;
    
    ## update cached value
    LJ::MemCache::incr([$userid, "friend_q_cnt:$userid"]);

    1;
}

sub load {
    my $class = shift;
    my $userid = shift;

    my $u = LJ::load_userid($userid);
    my $dbcr = LJ::get_cluster_reader($u->clusterid);
    my $sth = $dbcr->prepare("
                SELECT * 
                FROM friending_actions_q 
                WHERE
                    userid = ?
                ORDER BY rec_id
                ");
    $sth->execute($u->userid);
    my @actions = ();
    while (my $h = $sth->fetchrow_hashref){
        push @actions => $h;
    }

    return @actions;
}

sub empty {
    my $class  = shift;
    my $userid = shift;
    my $rec_id = shift;

    my $u = LJ::load_userid($userid);
    my $dbcw = LJ::get_cluster_master($u->clusterid);
    my $rec_id_st = $rec_id ? " AND rec_id <= " . int($rec_id) : "";
    $dbcw->do("DELETE 
               FROM friending_actions_q 
               WHERE 
                     userid = ?
                     $rec_id_st
               ", undef, $userid)
        or die "Can't flush records from friending_actions_q: " . DBI->errstr;
    
    LJ::MemCache::delete([$userid, "friend_q_cnt:$userid"]);

    return 1;
}

1;

