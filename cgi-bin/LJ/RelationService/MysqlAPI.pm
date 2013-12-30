package LJ::RelationService::MysqlAPI;

############################################################
#
#        WE NEED REALIZE SMART CACHING/CHUNK CACHING
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
use LJ::Utils::List;
use LJ::MemCacheProxy;
use LJ::RelationService::Const;

require 'ljdb.pl';

sub create_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    if ( $type eq 'F' ) {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_create_relation_to_type_f_new($u, $target, %opts);
        } else {
            return $class->_create_relation_to_type_f_old($u, $target, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_create_relation_to_type_r($u, $target, %opts);
    } elsif ($type eq 'PC') {
        return $class->_create_relation_to_type_f_old($u, $target, %opts);
    } else {
        return $class->_create_relation_to_type_other($u, $target, $type, %opts);
    }
}

sub _create_relation_to_type_f_new {
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

    $dbh->begin_work();

    if ($dbh->err) {
        return 0;
    }

    $dbh->do(qq[
            REPLACE INTO friends  (
                userid, friendid, groupmask
            ) VALUES (
                ?, ?, 1
            )
        ],
        undef, 
        $uid,
        $tid
    );

    if ($dbh->err) {
        $dbh->rollback();
        return 0;
    }

    $dbh->do(qq[
            REPLACE INTO friends  (
                userid, friendid, groupmask
            ) VALUES (
                ?, ?, 1
            )
        ],
        undef, 
        $tid,
        $uid
    );

    if ($dbh->err) {
        $dbh->rollback();
        return 0;
    }

    $dbh->commit();

    if ($dbh->err) {
        return 0;
    }

    # Invalidate user memcache
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "friends2:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:old:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:new:F:$uid"]);

    # Invalidate target memcache
    LJ::MemCacheProxy::delete([$tid, "friendofs:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "friendofs2:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELS_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:old:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:new:F:$tid"]);
    
    return 1;
}

sub _create_relation_to_type_f_old {
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

    $opts{fgcolor}   ||= 0;
    $opts{bgcolor}   ||= 16777215;
    $opts{groupmask} ||= 1;

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

    # Invalidate user memcache
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "friends2:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:PC:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:old:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:new:F:$uid"]);

    # Invalidate target memcache
    LJ::MemCacheProxy::delete([$tid, "friendofs:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "friendofs2:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELS_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:PC:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:old:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:new:F:$tid"]);
    
    return 1;
}

# Maybe in this method we must use transaction,
# because we write into 2 table and its an atomic action
sub _create_relation_to_type_r {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $cidu = $u->clusterid;
    my $cidt = $target->clusterid;

    return 0 unless $cidu;
    return 0 unless $cidt;

    my $dbhu = LJ::get_cluster_master($u);
    my $dbht = LJ::get_cluster_master($target);

    return 0 unless $dbhu;
    return 0 unless $dbht;

    $opts{filtermask} ||= 1;

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
        $opts{filtermask}
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
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:R:$uid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:R:$tid"]);

    return 1;
}

sub _create_relation_to_type_other {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    my $dbh = LJ::get_db_writer();

    return 0 unless $dbh;

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

    return 0 if $dbh->err;

    # set in memcache
    LJ::_set_rel_memcache($uid, $tid, $type, 1);

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:$type:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$uid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$tid"]);

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
        if ($target eq '*') {
            return $class->_remove_all_relations_destinations_to_type_other($u, $type);
        } elsif ($u eq '*') {
            return $class->_remove_all_relations_sources_to_type_other($target, $type);
        } else {
            return $class->_remove_relation_to_type_other($u, $target, $type);
        }
    }
}

# Remove two relation after prod
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

    # Invalidate user memcache
    LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "friends2:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:PC:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:old:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:new:F:$uid"]);

    # Invalidate target memcache
    LJ::MemCacheProxy::delete([$tid, "friendofs:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "friendofs2:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELS_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:PC:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$tid:$uid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:old:F:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:new:F:$tid"]);

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

    return 0 unless $cidu;
    return 0 unless $cidt;

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
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:R:$uid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:R:$tid"]);

    return 1;
}

sub _remove_all_relations_destinations_to_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;

    my $uid = $u->id;

    return 0 unless $uid;

    my $rels = $class->_find_relation_destinations(
        $u, $type, dont_set_cache => 1
    );

    # non-clustered global reluser table
    my $dbh = LJ::get_db_writer();

    unless ($dbh) {
        return 0;
    }

    $dbh->do(qq[
            DELETE FROM
                reluser
            WHERE
                type = ?
            AND
                userid = ?
        ],
        undef,
        $type,
        $uid
    );

    if ($dbh->err) {
        return 0;
    }

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$uid"]);

    foreach my $tid (@$rels) {
        # Invalidate user cache
        LJ::MemCacheProxy::delete("rel:$uid:$tid:$type");
        LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:$type:$uid:$tid"]);

        # Invalidate target cache
        LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$tid"]);
        LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$tid"]);
    }

    return 1;
}

sub _remove_all_relations_sources_to_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;

    my $uid = $u->id;

    return 0 unless $uid;

    my $rels = $class->_find_relation_sources(
        $u, $type, dont_set_cache => 1
    );

    # non-clustered global reluser table
    my $dbh = LJ::get_db_writer();

    unless ($dbh) {
        return 0;
    }

    $dbh->do(qq[
            DELETE FROM
                reluser
            WHERE
                type = ?
            AND
                targetid = ?
        ],
        undef,
        $type,
        $uid
    );

    if ($dbh->err) {
        return 0;
    }

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$uid"]);

    foreach my $tid (@$rels) {
        LJ::MemCacheProxy::delete("rel:$tid:$uid:$type");

        # Invalidate target cache
        LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$tid"]);
        LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_REL_KEY_PREFIX:$type:$tid:$uid"]);
        LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$tid"]);
    }   

    return 1;
}

sub _remove_relation_to_type_other {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    my $dbh = LJ::get_db_writer();

    unless ($dbh) {
        return 0;
    }

    $dbh->do(qq[
            DELETE FROM
                reluser
            WHERE
                type = ?
            AND
                userid = ?
            AND
                targetid = ?
        ],
        undef,
        $type,
        $uid,
        $tid
    );

    if ($dbh->err) {
        return 0;
    }
    
    # Update cache
    LJ::_set_rel_memcache($uid, $tid, $type, 0);

    # Invalidate user cache
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:$type:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$uid"]);

    # Invalidate target cache
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$tid"]);
    LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$tid"]);

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
# opts: keys, edges
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

    unless (@{$opts->{edges}}) {
        return 0;
    }

    my $mode   = $opts->{mode} eq 'clear' ? 'clear' : 'set';
    my $memval = $mode eq 'set' ? 1 : 0;

    my @reluser = (); # [userid, targetid, type]

    foreach my $edge (@{$opts->{edges}}) {
        my ($userid, $targetid, $type) = @$edge;

        $userid   = LJ::want_userid($userid);
        $targetid = LJ::want_userid($targetid);

        next unless $type;
        next unless $userid;
        next unless $targetid;

        push @reluser, [$userid, $targetid, $type];
    }

    # do global reluser updates
    if (@reluser) {
        my $dbh = LJ::get_db_writer();

        unless ($dbh) {
            return 0;
        }

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

        if ($dbh->err) {
            return 0;
        }

        # $_ = [userid, targetid, type] for each iteration
        foreach my $rel (@reluser) {
            my ($uid, $tid, $type) = @$rel;

            LJ::_set_rel_memcache(@$rel, $memval);

            # Invalidate user cache
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$uid"]);
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:$type:$uid:$tid"]);
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$uid"]);

            # Invalidate target cache
            LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$tid"]);
            LJ::MemCacheProxy::delete([$tid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$tid"]);
        }
    }

    return 1;
}

sub is_relation_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    if ($type eq 'R') {
        return $class->find_relation_attributes($u, $target, $type, %opts) ? 1 : 0;
    } elsif ($type eq 'F') {
        return $class->find_relation_attributes($u, $target, $type, %opts) ? 1 : 0;
    } elsif ($type eq 'PC') {
        return $class->find_relation_attributes($u, $target, $type, %opts) ? 1 : 0;
    } else {
        return $class->_is_relation_to_other($u, $target, $type, %opts);
    }
}

sub _is_relation_to_other {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;
    
    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    # did we get something from memcache?
    my $val = LJ::_get_rel_memcache($uid, $tid, $type);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    unless ($dbh) {
        return 0;
    }

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                reluser
            WHERE
                userid = ?
            AND
                targetid = ?
            AND
                type = ?
        ],
        undef,
        $uid, 
        $tid,
        $type
    );

    if ($dbh->err) {
        return 0;
    }

    # set in memcache
    LJ::_set_rel_memcache($uid, $tid, $type, $val);

    # return and set request cache
    return $val;
}

sub is_relation_type_to {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $types  = shift;
    my %opts   = @_;

    my $uid = $u->id;
    my $tid = $target->id;

    return 0 unless $uid;
    return 0 unless $tid;

    $types = join ",", map {"'$_'"} @$types;

    my $dbh = LJ::get_db_writer();

    unless ($dbh) {
        return 0;
    }

    my $relcount = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                reluser
            WHERE
                userid = ?
            AND
                targetid = ?
            AND
                type
            IN
                ($types)
        ],
        undef,
        $uid,
        $tid
    );

    return $relcount;
}

## friends
sub find_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    return unless $u;
    return unless $type;

    my $ids = $class->_find_relation_destinations($u, $type, %opts);

    return unless $ids;

    if (my $filters = $opts{filters}) {
        $class->_filter($u, $ids, $filters);
    }

    return @$ids;
}

sub _find_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ( $type eq 'F' ) {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_find_relation_destinations_type_f_new($u, %opts);
        } else {
            return $class->_find_relation_destinations_type_f_old($u, %opts);
        }
    } elsif ($type eq 'R')  {
        return $class->_find_relation_destinations_type_r($u, %opts);
    } elsif ($type eq 'PC') {
        return $class->_find_relation_destinations_type_f_old($u, %opts);
    } else {
        return $class->_find_relation_destinations_type_other($u, $type, %opts);
    }
}

sub _find_relation_destinations_type_f_new {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELS_KEY_PREFIX:F:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh  = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids    = $dbh->selectcol_arrayref(qq[
            SELECT
                f1.friendid
            FROM
                friends as f1
            LEFT JOIN
                friends as f2
            ON
                f1.friendid = f2.userid
            LEFT JOIN
                user as u
            ON
                f1.friendid = u.userid
            WHERE
                f1.userid = ?
            AND
                f2.friendid = ?
            AND
                u.journaltype in ('P', 'Y')
            $sqlimit
        ],
        undef,
        $uid,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = sort {
        $a <=> $b
    } @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @uids;
    }

    my $pack = pack 'N*', ($limit, @uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, 3600);
        }
    }

    return \@uids;
}

sub _find_relation_destinations_type_f_old {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "friends2:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh  = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids    = $dbh->selectcol_arrayref(qq[
            SELECT
                friendid
            FROM
                friends
            WHERE
                userid = ?
            ORDER BY
                friendid
            $sqlimit
        ],
        undef, $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @uids;
    }

    my $pack = pack 'N*', ($limit, @uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, 3600);
        }
    }

    return $uids;
}

sub _find_relation_destinations_type_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELS_KEY_PREFIX:R:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids = $dbh->selectcol_arrayref(qq[
            SELECT
                subscriptionid
            FROM
                subscribers2
            WHERE
                userid = ?
            ORDER BY
                subscriptionid
            $sqlimit
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my $pack = pack 'N*', ($limit, @$uids);

    LJ::MemCacheProxy::set($memkey, $pack, $MEMCACHE_RELS_TIMECACHE);

    return $uids;
}

sub _find_relation_destinations_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELS_KEY_PREFIX:$type:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if ($val) {
        my @ids = unpack('N*', $val);
        return \@ids;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $uids = $dbh->selectcol_arrayref(qq[
            SELECT
                targetid 
            FROM
                reluser 
            WHERE
                userid = ? 
            AND
                type = ?
            ORDER BY
                targetid
        ],
        undef,
        $uid,
        $type
    );

    unless ($opts{dont_set_cache}) {
        LJ::MemCacheProxy::set($key, pack('N*', @$uids), $MEMCACHE_RELS_TIMECACHE);
    }

    return $uids;
}

## friendofs
sub find_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    return unless $u;
    return unless $type;

    my $ids = $class->_find_relation_sources($u, $type, %opts);

    return unless $ids;

    if (my $filters = $opts{filters}) {
        $class->_filter($u, $ids, $filters);
    }

    return @$ids;
}

sub _find_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ($type eq 'F') {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_find_relation_sources_type_f_new($u, %opts);
        } else {
            return $class->_find_relation_sources_type_f_old($u, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_find_relation_sources_type_r($u, %opts);
    } elsif ($type eq 'PC') {
        return $class->_find_relation_sources_type_pc($u, %opts);
    } else {
        return $class->_find_relation_sources_type_other($u, $type, %opts);
    }
}

sub _find_relation_sources_type_f_new {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    
    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:F:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids    = $dbh->selectcol_arrayref(qq[
            SELECT
                f1.userid
            FROM
                friends as f1
            LEFT JOIN
                friends as f2
            ON
                f1.userid = f2.friendid
            LEFT JOIN
                user as u
            ON
                f1.userid = u.userid
            WHERE
                f1.friendid = ?
            AND
                f2.userid = ?
            AND
                u.journaltype in ('P', 'Y')
            $sqlimit
        ],
        undef,
        $uid,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = sort {
        $a <=> $b
    } @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @uids;
    }

    my $pack = pack 'N*', ($limit, @uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, 3600);
        }
    }

    return \@uids;
}

sub _find_relation_sources_type_f_old {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    
    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "friendofs2:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids    = $dbh->selectcol_arrayref(qq[
            SELECT
                userid
            FROM
                friends
            WHERE
                friendid = ?
            ORDER BY
                userid
            $sqlimit
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @uids;
    }

    my $pack = pack 'N*', ($limit, @uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, 3600);
        }
    }

    return $uids;
}

sub _find_relation_sources_type_pc {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    
    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:PC:$uid"];

    ## check cache first
    unless ($force) {
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
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids    = $dbh->selectcol_arrayref(qq[
            SELECT
                f.userid
            FROM
                friends as f
            LEFT JOIN
                user as u
            ON
                f.userid = u.userid
            WHERE
                f.friendid = ?
            AND
                u.journaltype = 'C'
            $sqlimit
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = sort {
        $a <=> $b
    } @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @uids;
    }

    my $pack = pack 'N*', ($limit, @uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, 3600);
        }
    }

    return \@uids;
}

sub _find_relation_sources_type_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:R:$uid"];

    unless ($force) {
        if (my $pack = LJ::MemCacheProxy::get($memkey)) {
            my ($slimit, @uids) = unpack("N*", $pack);
            # value in memcache is good if stored limit (from last time)
            # is >= the limit currently being requested.  we just may
            # have to truncate it to match the requested limit

            if ($slimit >= $limit) {
                if (scalar @uids > $limit) {
                    @uids = @uids[0..$limit-1];
                }

                return \@uids;
            }

            # value in memcache is also good if number of items is less
            # than the stored limit... because then we know it's the full
            # set that got stored, not a truncated version.
            return \@uids if @uids < $slimit;
        }
    }

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids = $dbh->selectcol_arrayref(qq[
            SELECT
                userid
            FROM
                subscribersleft
            WHERE
                subscriptionid = ?
            ORDER BY
                userid
            $sqlimit
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    my @uids = @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @$uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @$uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @$uids;
    }

    my $pack = pack 'N*', ($limit, @$uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            LJ::MemCacheProxy::set($memkey, $pack, $MEMCACHE_RELSOF_TIMECACHE);
        }
    }

    return $uids;
}

sub _find_relation_sources_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $force  = $opts{force};
    my $limit  = $opts{limit} || 50000;
    my $memkey = [$uid, "$MEMCACHE_RELSOF_KEY_PREFIX:$type:$uid"];

    unless ($force) {
        if (my $pack = LJ::MemCacheProxy::get($memkey)) {
            my ($slimit, @uids) = unpack("N*", $pack);
            # value in memcache is good if stored limit (from last time)
            # is >= the limit currently being requested.  we just may
            # have to truncate it to match the requested limit

            if ($slimit >= $limit) {
                if (scalar @uids > $limit) {
                    @uids = @uids[0..$limit-1];
                }

                return \@uids;
            }

            # value in memcache is also good if number of items is less
            # than the stored limit... because then we know it's the full
            # set that got stored, not a truncated version.
            return \@uids if @uids < $slimit;
        }
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $sqlimit = $limit ? " LIMIT $limit" : '';
    my $uids = $dbh->selectcol_arrayref(qq[
            SELECT
                userid
            FROM
                reluser
            WHERE
                targetid = ?
            AND
                type = ?
            ORDER BY
                userid
            $sqlimit
        ],
        undef,
        $uid,
        $type
    );

    my @uids = @$uids;

    # We cant cache more then 200000 (~ 1MB)
    if (scalar @$uids > $MAX_COUNT_FOR_CACHE_REL_IDS) {
        splice @$uids, $MAX_COUNT_FOR_CACHE_REL_IDS, scalar @$uids;
    }

    my $pack = pack 'N*', ($limit, @$uids);

    if ($pack) {
        if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
            warn "TO MUCH pack [uid=$uid]. max count must be less";
        } else {
            unless ($opts{dont_set_cache}) {
                LJ::MemCacheProxy::set($memkey, $pack, $MEMCACHE_RELSOF_TIMECACHE);
            }
        }
    }

    return $uids;
}

sub load_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ($type eq 'F') {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_load_relation_destinations_f_new($u, %opts);
        } else {
            return $class->_load_relation_destinations_f_old($u, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_load_relation_destinations_r($u, %opts);
    } elsif ($type eq 'PC') {
        return $class->_load_relation_destinations_f_old($u, %opts);
    }

    return {};
}

sub _load_relation_destinations_f_new {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my %res  = ();
    my $key  = [$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"];
    my @data = ();

    if (my $val = LJ::MemCacheProxy::get($key)) {
        @data = unpack 'N*', $val;
    } else {
        return {} if $opts{memcache_only};

        my $dbh = LJ::get_db_writer();

        return unless $dbh;

        my $name = "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid";
        my $lock = LJ::get_lock($dbh, "global", $name);

        return unless $lock;

        # in lock, try memcache
        if (my $val = LJ::MemCacheProxy::get($key)) {
            @data = unpack 'N*', $val;
        } else {
            my $data = $dbh->selectcol_arrayref(qq[
                    SELECT
                        f1.friendid, f1.groupmask
                    FROM
                        friends as f1
                    LEFT JOIN
                        friends as f2
                    ON
                        f1.friendid = f2.userid
                    LEFT JOIN
                        user as u
                    ON
                        f1.friendid = u.userid
                    WHERE
                        f1.userid = ?
                    AND
                        f2.friendid = ?
                    AND
                        u.journaltype in ('P', 'Y')
                ],
                {
                    Columns => [1,2]
                },
                $uid,
                $uid
            );

            if ($dbh->err) {
                LJ::release_lock($dbh, "global", $name);
                return;
            }

            @data = sort {
                $a <=> $b
            } @$data;

            my $pack = pack 'N*', @$data;

            if ($pack) {
                if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
                    warn "TO MUCH pack [uid=$uid]. max count must be less";
                } else {
                    LJ::MemCacheProxy::set($key, $pack, $MEMCACHE_RELS_TIMECACHE);
                }
            }
        }

        # finished with lock, release it
        LJ::release_lock($dbh, "global", $name);
    }

    my $mask  = $opts{mask};
    my $count = $#data;

    foreach (my $i = 0; $i < $count; $i += 2) {
        next if $mask && ! ($data[$i+3] + 0 & $mask + 0);

        $res{$data[$i]} = {
            groupmask => $data[$i+1],
        };
    }

    return \%res;
}

sub _load_relation_destinations_f_old {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my %res  = ();
    my $key  = [$uid, "friends:$uid"];
    my @data = ();

    if (my $val = LJ::MemCacheProxy::get($key)) {
        $val =~ s/^\d//;

        @data = unpack '(NH6H6NC)*', $val;
    } else {
        return {} if $opts{memcache_only};

        my $dbh = LJ::get_db_writer();

        return unless $dbh;

        my $name = "$MEMCACHE_RELS_KEY_PREFIX:F:$uid";
        my $lock = LJ::get_lock($dbh, "global", $name);

        return unless $lock;

        # in lock, try memcache
        if (my $val = LJ::MemCacheProxy::get($key)) {
            $val =~ s/^\d//;

            @data = unpack '(NH6H6NC)*', $val;
        } else {
            my $data = $dbh->selectcol_arrayref(qq[
                    SELECT
                        friendid, fgcolor, bgcolor, groupmask, showbydefault
                    FROM
                        friends
                    WHERE
                        userid =? 
                ],
                {
                    Columns => [1,2,3,4,5]
                },
                $uid
            );

            if ($dbh->err) {
                LJ::release_lock($dbh, "global", $name);
                return;
            }

            @data = @$data;

            my $count = $#data;

            foreach (my $i = 0; $i < $count; $i += 5) {
                $data[$i+1] = sprintf("%06x", $data[$i+1]);
                $data[$i+2] = sprintf("%06x", $data[$i+2]);
            }

            my $pack = pack '(NH6H6NC)*', @data;

            $pack = 1 . $pack;

            if ($pack) {
                if (length $pack > $MAX_SIZE_FOR_PACK_STRUCT) {
                    warn "TO MUCH pack [uid=$uid]. max count must be less";
                } else {
                    LJ::MemCacheProxy::set($key, $pack, $MEMCACHE_RELS_TIMECACHE);
                }
            }
        }

        # finished with lock, release it
        LJ::release_lock($dbh, "global", $name);
    }

    my $mask  = $opts{mask};
    my $count = $#data;

    foreach (my $i = 0; $i < $count; $i += 5) {
        next if $mask && ! ($data[$i+3] + 0 & $mask + 0);

        $res{$data[$i]} = {
            fgcolor       => '#' . $data[$i+1],
            bgcolor       => '#' . $data[$i+2],
            groupmask     => $data[$i+3],
            showbydefault => $data[$i+4]
        };
    }

    return \%res;
}

sub _load_relation_destinations_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my %res  = ();
    my $key  = [$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid"];
    my @data = ();

    if (my $val = LJ::MemCacheProxy::get($key)) {
        @data = unpack 'N*', $val;
    } else {
        return if $opts{memcache_only};

        my $dbh = LJ::get_cluster_master($u);

        return unless $dbh;

        my $name = "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid";
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
                    ORDER BY
                        subscriptionid
                ],
                {
                    Columns => [1,2]
                },
                $uid
            );

            if ($dbh->err) {
                LJ::release_lock($dbh, "user", $name);
                return;
            }

            @data = @$data;

            LJ::MemCacheProxy::set($key, (pack 'N*', @data), $MEMCACHE_RELS_TIMECACHE);
        }

        LJ::release_lock($dbh, "user", $name);
    }

    my $filters      = $opts{filters} || {};
    my $filtrate     = 0;
    my $f_filtermask = $filters->{filtermask};

    {
        $filtrate = 1, last if $f_filtermask;
    }

    my $count = $#data;

    if ($filtrate) {
        $f_filtermask += 0;

        for (my $i = 0; $i < $count; $i += 2) {
            next unless $f_filtermask & $data[$i+1];

            $res{$data[$i]} = {
                filtermask => $data[$i+1]
            };
        }
    } else {
        for (my $i = 0; $i < $count; $i += 2) {
            $res{$data[$i]} = {
                filtermask => $data[$i+1]
            };
        }
    }

    return \%res;
}

sub count_relation_destinations {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ($type eq 'F') {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_count_relation_destinations_type_f_new($u, %opts);
        } else {
            return $class->_count_relation_destinations_type_f_old($u, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_count_relation_destinations_type_r($u, %opts);
    } elsif ($type eq 'PC') {
        return $class->_count_relation_destinations_type_f_old($u, %opts);
    } else {
        return $class->_count_relation_destinations_type_other($u, $type, %opts);
    }

    return 0;
}

sub _count_relation_destinations_type_f_new {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:new:F:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                friends as f1
            LEFT JOIN
                friends as f2
            ON
                f1.friendid = f2.userid
            LEFT JOIN
                user as u
            ON
                f1.friendid = u.userid
            WHERE
                f1.userid = ?
            AND
                f2.friendid = ?
            AND
                u.journaltype in ('P', 'Y')
        ],
        undef,
        $uid,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_destinations_type_f_old {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:old:F:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                friends
            WHERE
                userid = ?
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_destinations_type_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:R:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                subscribers2
            WHERE
                userid = ?
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_destinations_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSCOUNT_KEY_PREFIX:$type:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                reluser
            WHERE
                userid = ?
            AND
                type = ?
        ],
        undef,
        $uid,
        $type
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSCOUNT_TIMECACHE);

    return $val;
}

sub count_relation_sources {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    if ($type eq 'F') {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_count_relation_sources_type_f_new($u, %opts);
        } else {
            return $class->_count_relation_sources_type_f_old($u, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_count_relation_sources_type_r($u, %opts);
    } elsif ($type eq 'PC') {
        return $class->_count_relation_sources_type_f_old($u, %opts);
    } else {
        return $class->_count_relation_sources_type_other($u, $type, %opts);
    }

    return 0;
}

sub _count_relation_sources_type_f_new {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:new:F:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                friends as f1
            LEFT JOIN
                friends as f2
            ON
                f1.userid = f2.friendid
            LEFT JOIN
                user as u
            ON
                f1.userid = u.userid
            WHERE
                f1.friendid = ?
            AND
                f2.userid = ?
            AND
                u.journaltype in ('P', 'Y')
        ],
        undef,
        $uid,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSOFCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_sources_type_f_old {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:old:F:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                friends
            WHERE
                friendid = ?
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSOFCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_sources_type_r {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:R:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_cluster_master($u);

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                subscribersleft
            WHERE
                subscriptionid = ?
        ],
        undef,
        $uid
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSOFCOUNT_TIMECACHE);

    return $val;
}

sub _count_relation_sources_type_other {
    my $class = shift;
    my $u     = shift;
    my $type  = shift;
    my %opts  = @_;

    my $uid = $u->id;

    return unless $uid;

    my $key = [$uid, "$MEMCACHE_RELSOFCOUNT_KEY_PREFIX:$type:$uid"];
    my $val = LJ::MemCacheProxy::get($key);

    if (defined $val) {
        return $val;
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    $val = $dbh->selectrow_array(qq[
            SELECT
                COUNT(*)
            FROM
                reluser
            WHERE
                targetid = ?
            AND
                type = ?
        ],
        undef,
        $uid,
        $type
    );

    if ($dbh->err) {
        return;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_RELSOFCOUNT_TIMECACHE);

    return $val;
}

sub find_relation_attributes {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my $type   = shift;
    my %opts   = @_;

    return unless $u;
    return unless $target;

    if ($type eq 'F') {
        if (LJ::is_enabled('new_friends_and_subscriptions')) {
            return $class->_find_relation_attributes_f_new($u, $target, %opts);
        } else {
            return $class->_find_relation_attributes_f_old($u, $target, %opts);
        }
    } elsif ($type eq 'R') {
        return $class->_find_relation_attributes_r($u, $target, %opts);
    } elsif ($type eq 'PC') {
        return $class->_find_relation_attributes_f_old($u, $target, %opts);
    }

    return;
}

sub _find_relation_attributes_f_new {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = LJ::want_userid($u);
    my $tid = LJ::want_userid($target);

    return unless $uid;
    return unless $tid;

    my $key = [$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"];
    my $val = LJ::MemCacheProxy::get($key);

    # Check memcache
    if (defined $val) {
        unless ($val) {
            return;
        }

        my @vals = unpack 'NNN', $val;

        return {
            bgcolor   => $vals[2],
            fgcolor   => $vals[1],
            groupmask => $vals[0]
        };
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

    my $row = $dbh->selectrow_hashref(qq[
            SELECT
                f1.groupmask, f1.fgcolor, f1.bgcolor
            FROM
                friends as f1
            LEFT JOIN
                friends as f2
            ON
                f1.friendid = f2.userid
            WHERE
                f1.userid = ?
            AND
                f2.friendid = ?
            AND
                f1.friendid = ?
            AND 
                f2.userid = ?
        ],
        {
            Slice => {}
        },
        $uid,
        $uid,
        $tid,
        $tid
    );

    if ($row) {
        $val = pack 'NNN', (
            $row->{groupmask},
            $row->{fgcolor},
            $row->{bgcolor}
        );
    } else {
        $val = 0;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_REL_TIMECACHE);

    return $row;
}

sub _find_relation_attributes_f_old {
    my $class  = shift;
    my $u      = shift;
    my $target = shift;
    my %opts   = @_;

    my $uid = LJ::want_userid($u);
    my $tid = LJ::want_userid($target);

    return unless $uid;
    return unless $tid;

    my $key = [$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"];
    my $val = LJ::MemCacheProxy::get($key);

    # Check memcache
    if (defined $val) {
        unless ($val) {
            return;
        }

        my @vals = unpack 'NNN', $val;

        return {
            bgcolor   => $vals[2],
            fgcolor   => $vals[1],
            groupmask => $vals[0]
        };
    }

    my $dbh = LJ::get_db_writer();

    return unless $dbh;

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

    if ($row) {
        $val = pack 'NNN', (
            $row->{groupmask},
            $row->{fgcolor},
            $row->{bgcolor}
        );
    } else {
        $val = 0;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_REL_TIMECACHE);

    return $row;
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
    my $val = LJ::MemCacheProxy::get($key);

    # Check memcache
    if (defined $val) {
        unless ($val) {
            return;
        }

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

    if ($row) {
        $val = pack 'N', $row->{filtermask};
    } else {
        $val = 0;
    }

    LJ::MemCacheProxy::set($key, $val, $MEMCACHE_REL_TIMECACHE);

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
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"]);
    
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
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);
    LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid"]);

    return $cnt;
}

sub delete_and_purge_completely {
    my $class = shift;
    my $u     = shift;
    my %opts  = @_;
    
    return 0 unless $u;

    my $uid = $u->id;

    return 0 unless $uid;

    my $dbh = LJ::get_db_writer();

    if ($dbh) {
        $dbh->do("DELETE FROM reluser WHERE userid=?", undef, $uid);
        $dbh->do("DELETE FROM friends WHERE userid=?", undef, $uid);
        $dbh->do("DELETE FROM friends WHERE friendid=?", undef, $uid);
        $dbh->do("DELETE FROM reluser WHERE targetid=?", undef, $uid);
    }

    $dbh = LJ::get_cluster_master($u);

    if ($dbh) {
        $dbh->do("DELETE FROM subscribers2 WHERE userid = ?", undef, $uid);
        $dbh->do("DELETE FROM subscribersleft WHERE subscriptionid = ?", undef, $uid);
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

    return 0 unless $uid;

    my $mask   = $opts{mask};
    my $action = $opts{action};

    return 0 unless $mask;
    return 0 unless $action;

    if ($action eq 'add') {
        $action = '|'
    }

    if ($action eq 'del') {
        $action = '&'
    }

    return 0 unless $action =~ /^(?:\&|\|)$/;

    $mask = int($mask);

    if ($type eq 'F') {
        my $dbh = LJ::get_db_writer();

        return 0 unless $dbh;

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
            return 0;
        }

        # Its a very bad. Need smart cache. See a top at this file
        my @ids = $class->find_relation_destinations($u, 'F', %opts);

        foreach my $tid (@ids) {
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:old:F:$uid:$tid"]);
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:new:F:$uid:$tid"]);
        }

        LJ::MemCacheProxy::delete([$uid, "friends:$uid"]);
        LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:F:$uid"]);
    }

    if ($type eq 'R') {
        my $dbh = LJ::get_cluster_master($u);

        return 0 unless $dbh;

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
            return 0;
        }

        # Its a very bad. Need smart cache. See a top at this file
        my $rels = $class->load_relation_destinations($u, 'R', %opts);

        foreach my $tid (keys %$rels) {
            LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_REL_KEY_PREFIX:R:$uid:$tid"]);
        }

        LJ::MemCacheProxy::delete([$uid, "$MEMCACHE_RELSFULL_KEY_PREFIX:R:$uid"]);
    }

    return 1;
}

# Filters

sub _filter {
    my ($class, $u, $ids, $filters) = @_;

    return unless $filters;
    return unless ref $filters eq 'ARRAY';
    
    foreach my $filter (@$filters) {
        my $type   = $filter->{type};
        my $edge   = $filter->{edge};
        my $edgeof = $filter->{edgeof};

        next unless $type;
        next unless $edge || $edgeof;

        my $rels;

        if ($edgeof) {
            $rels = $class->_find_relation_sources($u, $edgeof);
        } elsif ($edge) {
            $rels = $class->_find_relation_destinations($u, $edge);
        }

        return unless $rels;

        if ($type eq 'exclude') {
            @$ids = LJ::Utils::List::exclude_sorted(undef, $ids, $rels);
        }
    }
}

1;
