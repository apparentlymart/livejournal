package LJ::RelationService::MysqlAPI;

############################################################
#
#        WE NEED REALIZE SMART CACHING 
#
# See uin _get_rel_memcache and _set_rel_memcache in ljrelation.pl
# it has to be the good decision in order that not invalidate in large quantities a cache
# or move to rs :)
#
############################################################

use strict;
use warnings;

# External modules
use Readonly;

# Internal modules
use LJ::MemCacheProxy;

Readonly my $MEMCACHE_REL_TIMECACHE     => 3600;
Readonly my $MEMCACHE_RELS_TIMECACHE    => 2 * 86400;
Readonly my $MEMCACHE_RELSOF_TIMECACHE  => 2 * 86400;
Readonly my $MEMCACHE_REL_KEY_PREFIX    => 'rel';
Readonly my $MEMCACHE_RELS_KEY_PREFIX   => 'rels';
Readonly my $MEMCACHE_RELSOF_KEY_PREFIX => 'relsof';

Readonly my $MAX_SIZE_FOR_PACK_STRUCT    => 950 * 1024; # 950Kb
Readonly my $MAX_COUNT_FOR_CACHE_REL_IDS => 200000;

##
sub create_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;
    
    if ( $type eq 'F' ) {
        return $class->_create_relation_to_type_f($u, $target, %opts);
    } elsif ($type eq 'R') {
        return $class->_create_relation_to_type_r($u, $target, %opts);
    } else {
        return $class->_create_relation_to_type_other($u, $target, $type, %opts);
    }
}

sub _create_relation_to_type_f {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $dbh = LJ::get_db_writer();

    return 0 unless $dbh;

    my $cnt = $dbh->do(qq[
            REPLACE INTO friends  (
                userid, friendid, fgcolor, bgcolor, groupmask
            ) VALUES (
                ?, ?, ?, ?, ?
            )
        ],
        undef, 
        $uid,
        $tid,
        $opts{fgcolor},
        $opts{bgcolor},
        $opts{groupmask}
    );

    if ($dbh->err) {
        return 0;
    }

    # invalidate memcache of friends
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "friends2:$uid"]);

    LJ::MemCacheProxy::delete([$tid, "friendofs:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "friendofs2:$tid"]);

    LJ::MemCacheProxy::delete([$uid, "frgmask:$uid:$tid"]);

    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:F:$uid:$tid"]);
    
    return 1;
}

# Maybe in this method we must use transaction,
# because we write into 2 table and its an atomic action
sub _create_relation_to_type_r {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %args   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $cidu = $u->clusterid;
    my $cidt = $target->clusterid;

    return unless $cidu;
    return unless $cidt;

    my $dbhu = LJ::get_cluster_master($u);
    my $dbht = LJ::get_cluster_master($target);

    return 0 unless $dbhu;
    return 0 unless $dbht;

    my $cntu = $dbhu->do(qq[
            REPLACE INTO subscribers2 (
                userid, subscriptionid, filtermask
            ) VALUES (
                ?, ?, ?
            )
        ],
        undef,
        $uid,
        $tid,
        $args{filtermask}
    );

    if ($dbhu->err) {
        return 0;
    }

    my $cntt = $dbht->do(qq[
            REPLACE INTO subscribersleft (
                subscriptionid, userid
            ) VALUES (
                ?, ?
            )
        ],
        undef,
        $tid,
        $uid
    );

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$tid"]);

    return 1;
}

sub _create_relation_to_type_other {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $uid = $u->id;
    my $tid = $target->id;

    # set in database
    $dbh->do(qq[
            REPLACE INTO reluser (
                userid, targetid, type
            ) VALUES (
                ?, ?, ?
            )
        ],
        undef,
        $uid,
        $tid,
        $type
    );

    return if $dbh->err;

    # set in memcache
    LJ::_set_rel_memcache($uid, $tid, $type, 1);

    # drop list rel list
    LJ::MemCacheProxy::delete("rlist:dst:$type:" . $uid);
    LJ::MemCacheProxy::delete("rlist:src:$type:" . $tid);

    return 1;
}


sub remove_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    
    if ( $type eq 'F' ) {
        return $class->_remove_relation_to_type_f($u, $target);
    } elsif ($type eq 'R') {
        return $class->_remove_relation_to_type_r($u, $target);
    } else {
        return $class->_remove_relation_to_type_other($u, $target, $type);
    }
}

sub _remove_relation_to_type_f {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $dbh = LJ::get_db_writer();

    return 0 unless $dbh;

    my $cnt = $dbh->do(qq[
            DELETE FROM
                friends
            WHERE
                userid = ?
            AND
                friendid = ?
        ],
        undef,
        $uid,
        $tid
    );

    if ($dbh->err) {
        return 0;
    }

    # invalidate memcache of friends
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "friends2:$uid"]);

    LJ::MemCacheProxy::delete([$tid, "friendofs:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "friendofs2:$tid"]);

    LJ::MemCacheProxy::delete([$uid, "frgmask:$uid:$tid"]);

    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:F:$uid:$tid"]);

    return 1;
}

# Maybe in this method we must use transaction,
# because we write into 2 table and its an atomic action
sub _remove_relation_to_type_r {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $cidu = $u->clusterid;
    my $cidt = $target->clusterid;

    return unless $cidu;
    return unless $cidt;

    my $dbhu = LJ::get_cluster_master($u);
    my $dbht = LJ::get_cluster_master($target);

    return 0 unless $dbhu;
    return 0 unless $dbht;

    my $cntu = $dbhu->do(qq[
            DELETE FROM
                subscribers2
            WHERE
                userid = ?
            AND
                subscriptionid = ?
        ],
        undef,
        $uid,
        $tid
    );

    if ($dbhu->err) {
        return 0;
    }

    my $cntt = $dbht->do(qq[
            DELETE FROM
                subscribersleft
            WHERE
                subscriptionid = ?
            AND
                userid = ?
        ],
        undef,
        $tid,
        $uid
    );

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$tid"]);

    return 1;
}

sub _remove_relation_to_type_other {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;

    my $typeid = LJ::get_reluser_id($type)+0;
    my $userid = ref($u) ? $u->userid : $u;
    my $friendid = ref($friend) ? $friend->userid : $friend;

    my @caches_to_delete = ();
    my @rels = ($friendid);

    my $eff_type = $typeid ? $typeid : $type;
    if ($friendid eq '*') {
        @rels = $class->_find_relation_destinations_type_other($u, $type, dont_set_cache => 1);
        push @caches_to_delete, map {"rlist:src:$eff_type:$_"} @rels;
        push @caches_to_delete, "rlist:dst:$eff_type:$userid";

    } elsif ($userid eq '*') {
        @rels = $class->_find_relation_sources_type_other($friend, $type, dont_set_cache => 1);
        push @caches_to_delete, map {"rlist:dst:$eff_type:$_"} @rels;
        push @caches_to_delete, "rlist:src:$eff_type:$friendid";
    } else {
        push @caches_to_delete, "rlist:dst:$eff_type:$userid";
        push @caches_to_delete, "rlist:src:$eff_type:$friendid";
    }

    if ($typeid) {
        # clustered reluser2 table
        return undef unless $u->writer;

        $u->do("DELETE FROM reluser2 WHERE " . ($userid ne '*' ? ("userid=".$userid." AND ") : "") .
               ($friendid ne '*' ? ("targetid=".$friendid." AND ") : "") . "type=$typeid");

        return undef if $u->err;
    } else {
        # non-clustered global reluser table
        my $dbh = LJ::get_db_writer()
            or return undef;

        my $qtype = $dbh->quote($type);
        $dbh->do("DELETE FROM reluser WHERE " . ($userid ne '*' ? ("userid=".$userid." AND ") : "") .
                 ($friendid ne '*' ? ("targetid=".$friendid." AND ") : "") . "type=$qtype");

        return undef if $dbh->err;
    }
    
    # if one of userid or targetid are '*', then we need to note the modtime
    # of the reluser edge from the specified id (the one that's not '*')
    # so that subsequent gets on rel:userid:targetid:type will know to ignore
    # what they got from memcache
    $eff_type = $typeid || $type;
    if ($userid eq '*') {
        LJ::MemCacheProxy::set([$friendid, "relmodt:$friendid:$eff_type"], time());
    } elsif ($friendid eq '*') {
        LJ::MemCacheProxy::set([$userid, "relmodu:$userid:$eff_type"], time());

    # if neither userid nor targetid are '*', then just call _set_rel_memcache
    # to update the rel:userid:targetid:type memcache key as well as the
    # userid and targetid modtime keys
    } else {
        LJ::_set_rel_memcache($userid, $friendid, $eff_type, 0);
    }    

    # drop list rel lists
    foreach my $key (@caches_to_delete) {
        LJ::MemCacheProxy::delete($key);
    }   

    return 1;
}

sub set_rel_multi {
    my $class = shift;
    my $edges = shift;
    return _mod_rel_multi({ mode => 'set', edges => $edges });
}

sub clear_rel_multi {
    my $class = shift;
    my $edges = shift;
    return _mod_rel_multi({ mode => 'clear', edges => $edges });
}

# <LJFUNC>
# name: LJ::RelationService::MysqlAPI::_mod_rel_multi
# des: Sets/Clears relationship edges for lists of user tuples.
# args: keys, edges
# des-keys: keys: mode  => {clear|set}.
# des-edges: edges =>  array of arrayrefs of edges to set: [userid, targetid, type]
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all updates succeeded, otherwise undef
# </LJFUNC>
sub _mod_rel_multi {
    my $opts = shift;
    return undef unless @{$opts->{edges}};

    my $mode = $opts->{mode} eq 'clear' ? 'clear' : 'set';
    my $memval = $mode eq 'set' ? 1 : 0;

    my @reluser  = (); # [userid, targetid, type]
    my @reluser2 = ();
    foreach my $edge (@{$opts->{edges}}) {
        my ($userid, $targetid, $type) = @$edge;
        $userid = LJ::want_userid($userid);
        $targetid = LJ::want_userid($targetid);
        next unless $type && $userid && $targetid;

        my $typeid = LJ::get_reluser_id($type)+0;
        my $eff_type = $typeid || $type;

        LJ::MemCacheProxy::delete("rlist:src:$eff_type:$targetid");
        LJ::MemCacheProxy::delete("rlist:dst:$eff_type:$userid");

        # working on reluser or reluser2?
        push @{$typeid ? \@reluser2 : \@reluser}, [$userid, $targetid, $eff_type];
    }

    # now group reluser2 edges by clusterid
    my %reluser2 = (); # cid => [userid, targetid, type]
    my $users = LJ::load_userids(map { $_->[0] } @reluser2);
    foreach (@reluser2) {
        my $cid = $users->{$_->[0]}->{clusterid} or next;
        push @{$reluser2{$cid}}, $_;
    }
    @reluser2 = ();

    # try to get all required cluster masters before we start doing database updates
    my %cache_dbcm = ();
    foreach my $cid (keys %reluser2) {
        next unless @{$reluser2{$cid}};

        # return undef immediately if we won't be able to do all the updates
        $cache_dbcm{$cid} = LJ::get_cluster_master($cid)
            or return undef;
    }

    # if any error occurs with a cluster, we'll skip over that cluster and continue
    # trying to process others since we've likely already done some amount of db
    # updates already, but we'll return undef to signify that everything did not
    # go smoothly
    my $ret = 1;

    # do clustered reluser2 updates
    foreach my $cid (keys %cache_dbcm) {
        # array of arrayrefs: [userid, targetid, type]
        my @edges = @{$reluser2{$cid}};

        # set in database, then in memcache.  keep the two atomic per clusterid
        my $dbcm = $cache_dbcm{$cid};

        my @vals = map { @$_ } @edges;

        if ($mode eq 'set') {
            my $bind = join(",", map { "(?,?,?)" } @edges);
            $dbcm->do("REPLACE INTO reluser2 (userid, targetid, type) VALUES $bind",
                      undef, @vals);
        }

        if ($mode eq 'clear') {
            my $where = join(" OR ", map { "(userid=? AND targetid=? AND type=?)" } @edges);
            $dbcm->do("DELETE FROM reluser2 WHERE $where", undef, @vals);
        }

        # don't update memcache if db update failed for this cluster
        if ($dbcm->err) {
            $ret = undef;
            next;
        }

        # updates to this cluster succeeded, set memcache
        LJ::_set_rel_memcache(@$_, $memval) foreach @edges;
    }

    # do global reluser updates
    if (@reluser) {

        # nothing to do after this block but return, so we can
        # immediately return undef from here if there's a problem
        my $dbh = LJ::get_db_writer()
            or return undef;

        my @vals = map { @$_ } @reluser;

        if ($mode eq 'set') {
            my $bind = join(",", map { "(?,?,?)" } @reluser);
            $dbh->do("REPLACE INTO reluser (userid, targetid, type) VALUES $bind",
                     undef, @vals);
        }

        if ($mode eq 'clear') {
            my $where = join(" OR ", map { "userid=? AND targetid=? AND type=?" } @reluser);
            $dbh->do("DELETE FROM reluser WHERE $where", undef, @vals);
        }

        # don't update memcache if db update failed for this cluster
        return undef if $dbh->err;

        # $_ = [userid, targetid, type] for each iteration
        LJ::_set_rel_memcache(@$_, $memval) foreach @reluser;
    }

    return $ret;
}

sub is_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    if ($type eq 'R') {
        return $class->find_relation_attributes($u, $target, $type, %opts) ? 1 : 0;
    } else {
        return $class->_is_relation_to_other($u, $target, $type, %opts);
    }
}

sub _is_relation_to_other {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $type   = shift;
    my %opts   = @_;
    
    return undef unless $type && $u && $friend;

    my $userid = LJ::want_userid($u);
    my $friendid = LJ::want_userid($friend);

    my $typeid = LJ::get_reluser_id($type)+0;
    my $eff_type = $typeid || $type;

    my $key = "$userid-$friendid-$eff_type";
    return $LJ::REQ_CACHE_REL{$key} if defined $LJ::REQ_CACHE_REL{$key};

    # did we get something from memcache?
    my $memval = LJ::_get_rel_memcache($userid, $friendid, $eff_type);
    return $memval if defined $memval;

    # are we working on reluser or reluser2?
    my ($db, $table);
    if ($typeid) {
        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        $table = "reluser2";
    } else {
        # non-clustered reluser table
        $db ||= LJ::get_db_reader();
        $table = "reluser";
    }

    # get data from db, force result to be {0|1}
    my $dbval = $db->selectrow_array("SELECT COUNT(*) FROM $table ".
                                     "WHERE userid=? AND targetid=? AND type=? ",
                                     undef, $userid, $friendid, $eff_type)
        ? 1 : 0;

    # set in memcache
    LJ::_set_rel_memcache($userid, $friendid, $eff_type, $dbval);

    # return and set request cache
    return $LJ::REQ_CACHE_REL{$key} = $dbval;
}

sub is_relation_type_to {
    my $class  = shift;
    my $u      = shift;
    my $friend = shift;
    my $types  = shift;
    my %opts   = @_;
    
    return undef unless $u && $friend;
    return undef unless ref $types eq 'ARRAY';

    my $userid = LJ::want_userid($u);
    my $friendid = LJ::want_userid($friend);

    $types = join ",", map {"'$_'"} @$types;

    my $dbh = LJ::get_db_writer();
    my $relcount = $dbh->selectrow_array("SELECT COUNT(*) FROM reluser ".
                                         "WHERE userid=$userid AND targetid=$friendid ".
                                         "AND type IN ($types)");
    return $relcount;
}

## friends
sub find_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ( $type eq 'F' ) {
        return $class->_find_relation_destinations_type_f($u, %opts);
    } else {
        return $class->_find_relation_destinations_type_other($u, $type, %opts);
    }
}

sub _find_relation_destinations_type_f {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    my $uids  = $class->_friend_friendof_uids($u, 
                        %opts,
                        limit     => $opts{limit}, 
                        mode      => "friends",
                        );
    return @$uids;
}

sub _find_relation_destinations_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $userid = $u->userid;
    my $typeid = LJ::get_reluser_id($type)+0;
    my $uids;

    my $eff_type = $typeid ? $typeid : $type;
    my $cached_data = LJ::MemCacheProxy::get("rlist:dst:$eff_type:$userid");
    if ($cached_data) {
        my @userids = unpack('V*', $cached_data);
        return @userids;
    }

    if ($typeid) {
        # clustered reluser2 table
        my $db = LJ::get_cluster_reader($u);
        $uids = $db->selectcol_arrayref("
            SELECT targetid 
            FROM reluser2 
            WHERE userid=? 
              AND type=?
        ", undef, $userid, $typeid);
    } else {
        # non-clustered reluser global table
        my $db = LJ::get_db_reader();
        $uids = $db->selectcol_arrayref("
            SELECT targetid 
            FROM reluser 
            WHERE userid=? 
              AND type=?
        ", undef, $userid, $type);
    }

    unless ($opts{dont_set_cache}) {
        my $packed = pack('V*', @$uids);
        LJ::MemCacheProxy::set("rlist:dst:$eff_type:$userid", $packed, 24 * 3600);
    }

    return @$uids;
}

## friendofs
sub find_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ($type eq 'F') {
        return $class->_find_relation_sources_type_f($u, %opts);
    } elsif ($type eq 'R') {
        return $class->_find_relation_sources_type_r($u, %opts);
    } else {
        return $class->_find_relation_sources_type_other($u, $type, %opts);
    }
}

sub _find_relation_sources_type_f {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    my $uids  = $class->_friend_friendof_uids($u, 
                        %opts,
                        limit     => $opts{limit}, 
                        mode      => "friendofs",
                        );
    return @$uids;
}

sub _find_relation_sources_type_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    my $limit  = int($opts{limit});
    my $memkey = [$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$uid"];

    if (my $pack = LJ::MemCacheProxy::get($memkey)) {
        my ($slimit, @uids) = unpack("N*", $pack);
        # value in memcache is good if stored limit (from last time)
        # is >= the limit currently being requested.  we just may
        # have to truncate it to match the requested limit

        if ($slimit >= $limit) {
            if (scalar @uids > $limit) {
                return @uids[0..$limit-1];
            }

            return @uids;
        }

        # value in memcache is also good if number of items is less
        # than the stored limit... because then we know it's the full
        # set that got stored, not a truncated version.
        return @uids if @uids < $slimit;
    }

    my $uids = $dbh->selectcol_arrayref(qq[
            SELECT
                userid
            FROM
                subscribersleft
            WHERE
                subscriptionid = ?
            LIMIT
                0, $limit
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @$uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @$uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @$uids;
    }

    ## do not cache if $nolimit option is in use,
    ## because with disabled limit we might put in the cache
    ## much more data than usually required.

    my $pack = pack 'N*', ($limit, @$uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, $MEMCACHE_RELSOF_TIMECACHE);
        }
    }

    return @$uids;
}

sub _find_relation_sources_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $userid = $u->userid;
    my $typeid = LJ::get_reluser_id($type)+0;
    my $uids;

    my $eff_type = $typeid ? $typeid : $type;
    my $cached_data = LJ::MemCacheProxy::get("rlist:src:$eff_type:$userid");
    if ($cached_data) {
        my @userids = unpack('V*', $cached_data);
        return @userids;
    }

    if ($typeid) {
        # clustered reluser2 table
        my $db = LJ::get_cluster_reader($u);
        $uids = $db->selectcol_arrayref("
            SELECT userid 
            FROM reluser2 
            WHERE targetid=? 
              AND type=?
        ", undef, $userid, $typeid);
    } else {
        # non-clustered reluser global table
        my $db = LJ::get_db_reader();
        $uids = $db->selectcol_arrayref("
            SELECT userid 
            FROM reluser 
            WHERE targetid=? 
              AND type=?
        ", undef, $userid, $type);
    }

    unless ($opts{dont_set_cache}) {
        my $packed = pack('V*', @$uids);
        LJ::MemCacheProxy::set("rlist:src:$eff_type:$userid", $packed, 24 * 3600);
    }

    return @$uids;
}

# helper method since the logic for both friends and friendofs is so similar
sub _friend_friendof_uids {
    my $class = shift;
    my $u     = shift;
    my %args  = @_;

    my $mode    = $args{mode};
    my $limit   = $args{limit};
    my $nolimit = $args{nolimit} ? 1 : 0; ## use it with care

    my $memkey;

    if ($mode eq "friends") {
        $memkey = [$u->id, "friends2:" . $u->id];
    } elsif ($mode eq "friendofs") {
        $memkey = [$u->id, "friendofs2:" . $u->id];
    } else {
        die "mode must either be 'friends' or 'friendofs'";
    }

    ## check cache first
    if (my $pack = LJ::MemCacheProxy::get($memkey)) {
        my ($slimit, @uids) = unpack("N*", $pack);
        # value in memcache is good if stored limit (from last time)
        # is >= the limit currently being requested.  we just may
        # have to truncate it to match the requested limit

        if ($limit) {
            if ($slimit >= $limit) {
                if (@uids > $limit) {
                    @uids = @uids[0..$limit-1];
                }

                return \@uids;
            }
        }

        # value in memcache is also good if number of items is less
        # than the stored limit... because then we know it's the full
        # set that got stored, not a truncated version.
        return \@uids if @uids < $slimit;
    }

    my $sql     = '';
    my $sqlimit = $limit && !$nolimit ? " LIMIT $limit" : '';

    if ($mode eq 'friends'){
        $sql = "SELECT friendid FROM friends WHERE userid=? $sqlimit";
    } elsif ($mode eq 'friendofs'){
        $sql = "SELECT userid FROM friends WHERE friendid=? $sqlimit";
    } else {
        die "mode must either be 'friends' or 'friendofs'";
    }

    my $dbh  = LJ::get_db_reader();
    my $uids = $dbh->selectcol_arrayref($sql, undef, $u->id);

    if (not $nolimit and $uids and @$uids){
        # We cant cache more then 200000 (~ 1MB)
        if (scalar @$uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
            splice @$uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @$uids;
        }

        ## do not cache if $nolimit option is in use,
        ## because with disabled limit we might put in the cache
        ## much more data than usually required.

        my $pack = pack 'N*', ($limit, @$uids);

        if ($pack) {
            if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
                warn "TO MUCH pack. max count must be less";
            } else {
                LJ::MemCacheProxy::set($memkey, $pack, 3600);
            }
        }
    }

    return $uids;
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %args  = @_;

    if ($type eq 'F') {
        return $class->_load_relation_destinations_f($u, %args);
    } elsif ($type eq 'R') {
        return $class->_load_relation_destinations_r($u, %args);
    }

    return {}
}

## friends rows
sub _load_relation_destinations_f {
    my $class = shift;
    my $u     = shift;
    my %args  = @_;

    die 'Expected parameter $u LJ::RelationService::MysqlAPI::load_relation_destinations()' unless $u;

    my $mask          = $args{mask};
    my $force_db      = $args{force_db};
    my $memcache_only = $args{memcache_only};

    return unless $u->userid;
    return if $LJ::FORCE_EMPTY_FRIENDS{$u->userid};

    unless ($force_db) {
        if (my $memc = $class->_get_friends_memc($u->userid, $mask)) {
            return $memc;
        }
    }

    return {} if $memcache_only; # no friends

    # nothing from memcache, select all rows from the
    # database and insert those into memcache
    # then return rows that matched the given groupmask

    my $userid = $u->id;

    my $dbh = LJ::get_db_writer();

    my $lockname = "get_friends:$userid";
    my $release_lock = sub {
        LJ::release_lock($dbh, "global", $lockname);
    };

    # get a lock
    my $lock = LJ::get_lock($dbh, "global", $lockname);
    return {} unless $lock;

    # in lock, try memcache
    my $memc = $class->_get_friends_memc($userid, $mask);
    if ($memc) {
        $release_lock->();
        return $memc;
    }

    # inside lock, but still not populated, query db

    # memcache data info
    my $ver = 1;
    my $memkey = [$userid, "friends:$userid"];

    # columns we're selecting
    my @cols = qw(friendid fgcolor bgcolor groupmask showbydefault);

    my $mempack = $ver; # full packed string to insert into memcache, byte 1 is dversion
    my %friends = ();   # friends object to be returned, all groupmasks match

    my $sth = $dbh->prepare("SELECT friendid, fgcolor, bgcolor, groupmask, showbydefault " .
                            "FROM friends WHERE userid=?");
    $sth->execute($userid);
    die $dbh->errstr if $dbh->err;
    while (my @row = $sth->fetchrow_array) {
        # convert color columns to hex
        $row[$_] = sprintf("%06x", $row[$_]) foreach 1..2;

        my $newpack = pack('NH6H6NC', @row);
        last if length($mempack) + length($newpack) > $MAX_SIZE_FOR_PACK_STRUCT;

        $mempack .= $newpack;

        # unless groupmask matches, skip adding to %friends
        next if $mask && ! ($row[3]+0 & $mask+0);

        # add "#" to beginning of colors
        $row[$_] = "\#$row[$_]" foreach 1..2;

        my $fid = $row[0];
        my $idx = 1;
        foreach my $col (@cols[1..$#cols]) {
            $friends{$fid}->{$col} = $row[$idx];
            $idx++;
        }
    }

    LJ::MemCache::set($memkey, $mempack);

    # finished with lock, release it
    $release_lock->();

    return \%friends;
}

sub _load_relation_destinations_r {
    my $class = shift;
    my $u     = shift;
    my %args  = @_;

    my $uid = $u->id;

    return unless $uid;

    my %res  = ();
    my $key  = [$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"];
    my @data = ();

    if (my $val = LJ::MemCacheProxy::get($key)) {
        @data = unpack 'N*', $val;
    } else {
        return if $args{memcache_only};

        my $dbh = LJ::get_cluster_master($u);

        return unless $dbh;

        my $name = "$MEMCACHE_RELS_KEY_PREFIX:R:$uid";
        my $lock = LJ::get_lock($dbh, "user", $name);

        return unless $lock;

        # in lock, try memcache
        if (my $val = LJ::MemCacheProxy::get($key)) {
            @data = unpack 'N*', $val;
        } else {
            my $data = $dbh->selectcol_arrayref(qq[
                    SELECT
                        subscriptionid, filtermask
                    FROM
                        subscribers2
                    WHERE
                        userid = ?
                ],
                {
                    Columns => [1,2]
                },
                $uid
            );

            if ($dbh->err) {
                return;
            }

            @data = @$data;

            my $pack = pack 'N*', @data;

            if ($pack) {
                LJ::MemCacheProxy::set($key, $pack, $MEMCACHE_RELS_TIMECACHE);
            }
        }

        LJ::release_lock($dbh, "user", $name);
    }

    my $filters      = $args{filters} || {};
    my $filtrate     = 0;
    my $f_filtermask = $filters->{filtermask};

    {
        $filtrate = 1, last if $f_filtermask;
    }

    if ($filtrate) {
        $f_filtermask += 0;

        for (my $i = 0; $i < $#data; $i += 2) {
            next unless $f_filtermask & $data[$i+1];

            $res{$data[$i]} = {
                filtermask => $data[$i+1]
            };
        }
    } else {
        for (my $i = 0; $i < $#data; $i += 2) {
            $res{$data[$i]} = {
                filtermask => $data[$i+1]
            };
        }
    }

    return \%res;
}

sub _get_friends_memc {
    my $class  = shift;
    my $uid    = shift;
    my $mask   = shift;

    return unless $uid;

    my %res = ();
    my $val = LJ::MemCache::get([$uid, "friends:$uid"]);

    return undef unless $val;

    $val =~ s/^\d//;

    my @data = unpack '(NH6H6NC)*', $val;

    for (my $i = 0; $i < $#data; $i += 5) {
        next if $mask && ! ($data[$i+3]+0 & $mask+0);

        $res{$data[$i]} = {
            fgcolor       => '#' . $data[$i+1],
            bgcolor       => '#' . $data[$i+2],
            groupmask     => $data[$i+3],
            showbydefault => $data[$i+4],
        };
    }

    return \%res;
}

sub find_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    return undef unless $u;
    return undef unless $target;

    if ($type eq 'F') {
        return $class->_find_relation_attributes_f($u, $target, %opts);
    } elsif ($type eq 'R') {
        return $class->_find_relation_attributes_r($u, $target, %opts);
    }

    return undef;
}

sub _find_relation_attributes_r {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return unless $uid;
    return unless $tid;

    # Memcache key
    my $key = [$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"];

    # Check memcache
    if (my $val = LJ::MemCacheProxy::get($key)) {
        my @vals = unpack 'N', $val;

        return {
            filtermask => $vals[0]
        };
    }

    # Try load from db
    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    my $row = $dbh->selectrow_hashref(qq[
            SELECT
                filtermask
            FROM
                subscribers2
            WHERE
                userid = ?
            AND
                subscriptionid = ?
        ],
        {
            Slice => {}
        },
        $uid,
        $tid
    );

    return unless $row;

    my $pack = pack 'N', $row->{filtermask};

    if ($pack) {
        LJ::MemCacheProxy::set($key, $pack, $MEMCACHE_REL_TIMECACHE);
    }

    return $row;
}

sub _find_relation_attributes_f {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = LJ::want_userid($u);
    my $tid = LJ::want_userid($target);

    return undef unless $uid;
    return undef unless $tid;

    my $key = [$uid, "$MEMCACHE_REL_KEY_PREFIX:F:$uid:$tid"];

    # Check memcache
    if (my $val = LJ::MemCacheProxy::get($key)) {
        my @vals = unpack 'NNN', $val;

        return {
            bgcolor   => $vals[1],
            fgcolor   => $vals[2],
            groupmask => $vals[0]
        };
    }

    my $dbh = LJ::get_db_writer();

    return undef unless $dbh;

    my $row = $dbh->selectrow_hashref(qq[
            SELECT
                groupmask, fgcolor, bgcolor 
            FROM
                friends
            WHERE
                userid = ? 
            AND
                friendid = ?
        ],
        {
            Slice => {}
        },
        $uid,
        $tid
    );

    return unless $row;

    my $pack = pack 'NNN', (
        $row->{groupmask},
        $row->{fgcolor},
        $row->{bgcolor}
    );

    if ($pack) {
        LJ::MemCacheProxy::set($key, $pack, $MEMCACHE_REL_TIMECACHE);
    }

    return $row;
}


sub update_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    return 0 unless $u;
    return 0 unless $target;

    if ($type eq 'F') {
        return $class->_update_relation_attributes_f($u, $target, %opts);
    } elsif ($type eq 'R') {
        return $class->_update_relation_attributes_r($u, $target, %opts);
    }

    return 0;
}

sub _update_relation_attributes_f {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $dbh = LJ::get_db_writer();

    return 0 unless $dbh;

    my @sets = ();
    my @vals = ();

    foreach my $attr (qw(fgcolor bgcolor groupmask)) {
        if (exists $opts{$attr}) {
            push @sets, "$attr = ?";
            push @vals, $opts{$attr};
        }
    }

    return 1 unless @sets;
    return 1 unless @vals;

    my $sets = join ',', @sets;

    my $cnt = $dbh->do(qq[
            UPDATE
                friends
            SET
                $sets
            WHERE
                userid = ?
            AND
                friendid = ?
        ],
        undef,
        @vals,
        $uid,
        $tid
    );

    if ($dbh->err) {
        return 0;
    }

    # invalidate memcache of friends
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "frgmask:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:F:$uid:$tid"]);
    
    return 1;
}

sub _update_relation_attributes_r {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;
    return 0 unless $opts{filtermask};

    my $dbh = LJ::get_cluster_master($u);

    return 0 unless $dbh;

    my $cnt = $dbh->do(qq[
            UPDATE
                subscribers2
            SET
                filtermask = ?
            WHERE
                userid = ?
            AND
                subscriptionid = ?
        ],
        undef,
        $opts{filtermask},
        $uid,
        $tid
    );

    if ($dbh->err) {
        return 0;
    }

    # Invalidate
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);

    return $cnt;
}

sub delete_and_purge_completely {
    my $class = shift;
    my $u = shift;
    my %opts = @_;
    
    return unless $u;
    
    my $dbh = LJ::get_db_writer();

    if ($dbh) {
        $dbh->do("DELETE FROM reluser WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM friends WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $u->id);
        $dbh->do("DELETE FROM reluser WHERE targetid=?", undef, $u->id);
    }

    $dbh = LJ::get_cluster_master($u);

    if ($dbh) {
        $dbh->do("DELETE FROM subscribers2 WHERE userid = ?", undef, $u->id);
        $dbh->do("DELETE FROM subscribersleft WHERE subscriptionid = ?", undef, $u->id);
    }

    foreach my $type (LJ::get_relation_types()) {
        my $typeid = LJ::get_reluser_id($type) || 0;
        my $eff_type = $typeid || $type;

        my @rels = $class->_find_relation_sources_type_other($u, $type, dont_set_cache => 1);
        foreach my $uid (@rels) {
            LJ::MemCacheProxy::delete("rlist:dst:$eff_type:$uid");
        }

        LJ::MemCacheProxy::delete("rlist:src:$eff_type:" . $u->id);
        LJ::MemCacheProxy::delete("rlist:dst:$eff_type:" . $u->id);
    }

    return 1;
}

# Special methods which destroy architectural logic but are necessary for productivity

sub update_relation_attribute_mask_for_all {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $mask   = $opts{mask};
    my $action = $opts{action};

    return unless $mask;
    return unless $action;

    if ($action eq 'add') {
        $action = '|'
    }

    if ($action eq 'del') {
        $action = '&'
    }

    return unless $action =~ /^(?:\&|\|)$/;

    $mask = int($mask);

    if ($type eq 'F') {
        my $dbh = LJ::get_db_writer();

        return unless $dbh;

        my $cnt = $dbh->do(qq[
                UPDATE
                    friends
                SET
                    groupmask = groupmask $action ~(?)
                WHERE
                    userid = ?
            ],
            undef,
            $mask,
            $uid
        );

        if ($dbh->err) {
            return;
        }

        # Its a very bad. Need smart cache. See a top at this file
        my @ids = $class->find_relation_destinations($u, 'F', %opts, nolimit => 1);

        foreach my $tid (@ids) {
            LJ::MemCacheProxy::delete([$uid, "frgmask:$uid:$tid"]);
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:F:$uid:$tid"]);
        }

        LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
        LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    }

    if ($type eq 'R') {
        my $dbh = LJ::get_cluster_master($u);

        return unless $dbh;

        my $cnt = $dbh->do(qq[
                UPDATE
                    subscribers2
                SET
                    filtermask = filtermask $action ~(?)
                WHERE
                    userid = ?
            ],
            undef,
            $mask,
            $uid
        );

        if ($dbh->err) {
            return;
        }

        # Its a very bad. Need smart cache. See a top at this file
        my $rels = $class->load_relation_destinations($u, 'R', %opts);

        foreach my $tid (keys %$rels) {
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);
        }

        LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"]);
    }

    return 1;
}

1;
