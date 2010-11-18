package LJ::FriendQueue;
use strict;

sub count {
    my $class    = shift;
    my $userid   = shift;

    ## TODO: use memcached?

    my $u = LJ::load_userid($userid);
    my $dbcr = LJ::get_cluster_reader($u->clusterid);

    my ($count) = $dbcr->selectrow_array("
            SELECT count(1) 
            FROM friending_actions_q
            WHERE
                userid = ?
            ", undef, $u->userid)
        or warn "Can't select from friend_actions_q: " . DBI->errstr;
    
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
    
    $dbcw->do("INSERT INTO friending_actions_q
                (userid, friendid, action, etime, jobid)
                VALUES
                (?,?,?,?,?)", undef,
                $userid, $friendid, $action, $etime, $jobid)
        or die "Can't insert into friend_actions_q: " . DBI->errstr;
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

    return 1;
}

1;

