#!/usr/bin/perl

package LJ::Memories;
use strict;

# <LJFUNC>
# name: LJ::Memories::count
# class: web
# des: Returns the number of memories that a user has.
# args: uuobj
# des-uuobj: Userid or user object to count memories of.
# returns: Some number; undef on error.
# </LJFUNC>
sub count {
    my $u = shift;
    $u = LJ::want_user($u);
    return undef unless $u;

    # check memcache first
    my $count = LJ::MemCache::get([$u->{userid}, "memct:$u->{userid}"]);
    return $count if $count;

    # now count
    if ($u->{dversion} > 5) {
        my $dbcr = LJ::get_cluster_def_reader($u);
        $count = $dbcr->selectrow_array('SELECT COUNT(*) FROM memorable2 WHERE userid = ?',
                                        undef, $u->{userid});
        return undef if $dbcr->err;
    } else {
        my $dbh = LJ::get_db_writer();
        $count = $dbh->selectrow_array('SELECT COUNT(*) FROM memorable WHERE userid = ?',
                                       undef, $u->{userid});
        return undef if $dbh->err;
    }
    $count += 0;

    # now put in memcache and return it
    LJ::MemCache::set([$u->{userid}, "memct:$u->{userid}"], $count, 43200); # 12 hours
    return $count;
}

# <LJFUNC>
# name: LJ::Memories::create
# class: web
# des: Create a new memory for a user.
# args: uuobj, opts, kwids?
# des-uuobj: User id or user object to insert memory for.
# des-opts: Hashref of options that define the memory; keys = journalid, ditemid, des, security
# des-kwids: Optional; arrayref of keyword ids to categorize this memory under
# returns: 1 on success, undef on error
# </LJFUNC>
sub create {
    my ($u, $opts, $kwids) = @_;
    $u = LJ::want_user($u);
    return undef unless $u && %{$opts || {}};

    # make sure we got enough options
    my ($userid, $journalid, $ditemid, $des, $security) =
        ($u->{userid}, map { $opts->{$_} } qw(journalid ditemid des security));
    $userid += 0;
    $journalid += 0;
    $ditemid += 0;
    $security ||= 'public';
    $kwids ||= [ LJ::get_keyword_id($u, '*') ]; # * means no category
    $des = LJ::trim($des);
    return undef unless $userid && $journalid && $ditemid && $des && $security && @$kwids;
    return undef unless $security =~ /^(?:public|friends|private)$/;

    # we have valid data, now let's insert it
    if ($u->{dversion} > 5) {
        return undef unless $u->writer;

        # allocate memory id to use
        my $memid = LJ::alloc_user_counter($u, 'R');
        return undef unless $memid;

        # insert main memory
        $u->do("INSERT INTO memorable2 (userid, memid, journalid, ditemid, des, security) " .
               "VALUES (?, ?, ?, ?, ?, ?)", undef, $userid, $memid, $journalid, $ditemid, $des, $security);
        return undef if $u->err;

        # insert keywords
        my $val = join ',', map { "($u->{userid}, $memid, $_)" } @$kwids;
        $u->do("REPLACE INTO memkeyword2 (userid, memid, kwid) VALUES $val");

    } else {
        my $dbh = LJ::get_db_writer();
        return undef unless $dbh;

        # insert main memory
        $dbh->do("INSERT INTO memorable (userid, journalid, jitemid, des, security) " .
                 "VALUES (?, ?, ?, ?, ?)", undef, $userid, $journalid, $ditemid, $des, $security);
        return undef if $dbh->err;

        # insert keywords
        my $memid = $dbh->{mysql_insertid}+0;
        my $val = join ',', map { "($memid, $_)" } @$kwids;
        $dbh->do("REPLACE INTO memkeyword (memid, kwid) VALUES $val");
    }

    # clear out memcache
    LJ::MemCache::delete([$u->{userid}, "memct:$u->{userid}"]);
    return 1;
}

# <LJFUNC>
# name: LJ::Memories::delete_by_id
# class: web
# des: Deletes a bunch of memories by memid.
# args: uuboj, memids
# des-uuobj: User id or user object to delete memories of.
# des-memids: Arrayref of memids.
# returns: 1 on success; undef on error.
# </LJFUNC>
sub delete_by_id {
    my ($u, $memids) = @_;
    $u = LJ::want_user($u);
    $memids = [ $memids ] if $memids && !ref $memids; # so they can just pass a single thing...
    return undef unless $u && @{$memids || []};

    # setup
    my ($db, $table) = $u->{dversion} > 5 ?
                       (LJ::get_cluster_master($u), '2') :
                       (LJ::get_db_writer(), '');

    # if dversion 5, verify the ids
    my $in = join ',', map { $_+0 } @$memids;
    if ($u->{dversion} == 5) {
        $memids = $db->selectcol_arrayref("SELECT memid FROM memorable WHERE userid = ? AND memid IN ($in)",
                                          undef, $u->{userid});
        return undef if $db->err;
        return 1 unless @{$memids || []}; # if we got nothing, pretend success
        $in = join ',', map { $_+0 } @$memids;
    }

    # delete actual memory
    $db->do("DELETE FROM memorable$table WHERE userid = ? AND memid IN ($in)", undef, $u->{userid});
    return undef if $db->err;

    # delete keyword associations
    my $euser = $u->{dversion} > 5 ? "userid = $u->{userid} AND" : '';
    $db->do("DELETE FROM memkeyword$table WHERE $euser memid IN ($in)");

    # delete cache of count
    LJ::MemCache::delete([$u->{userid}, "memct:$u->{userid}"]);

    # success at this point, since the first delete succeeded
    return 1;
}

# <LJFUNC>
# name: LJ::Memories::get_keyword_counts
# class: web
# des: Get a list of keywords and the counts for memories, showing how many memories are under
#   each keyword.
# args: uuobj, opts?
# des-uuobj: User id or object of user.
# des-opts: Optional; hashref passed to _memory_getter, suggested keys are security and filter
#   if you want to get only certain memories in the keyword list
# returns: Hashref { kwid => count }; undef on error
# </LJFUNC>
sub get_keyword_counts {
    my ($u, $opts) = @_;
    $u = LJ::want_user($u);
    return undef unless $u;

    # get all of the user's memories that fit the filtering
    my $memories = LJ::Memories::get_by_user($u, { %{$opts || {}}, notext => 1 });
    return undef unless defined $memories; # error case
    return {} unless %$memories; # just no memories case
    my @memids = map { $_+0 } keys %$memories;

    # now let's get the keywords these memories use
    my $in = join ',', @memids;
    my $kwids;
    if ($u->{dversion} > 5) {
        my $dbcr = LJ::get_cluster_reader($u);
        $kwids = $dbcr->selectcol_arrayref("SELECT kwid FROM memkeyword2 WHERE userid = ? AND memid IN ($in)",
                                           undef, $u->{userid});
        return undef if $dbcr->err;
    } else {
        my $dbr = LJ::get_db_reader();
        $kwids = $dbr->selectcol_arrayref("SELECT kwid FROM memkeyword WHERE memid IN ($in)");
        return undef if $dbr->err;
    }

    # and now combine them
    my %res;
    $res{$_}++ foreach @$kwids;

    # done, return
    return \%res;
}

# <LJFUNC>
# name: LJ::Memories::get_keywordids
# class: web
# des: Get all keyword ids a user has used for a certain memory.
# args: uuobj, memid
# des-uuobj: User id or user object to check memory of.
# des-memid: Memory id to get keyword ids for.
# returns: Arrayref of keywordids; undef on error.
# </LJFUNC>
sub get_keywordids {
    my ($u, $memid) = @_;
    $u = LJ::want_user($u);
    $memid += 0;
    return undef unless $u && $memid;

    # definitive reader/master because this function is usually called when
    # someone is on an edit page.
    my $kwids;
    if ($u->{dversion} > 5) {
        my $dbcr = LJ::get_cluster_def_reader($u);
        $kwids = $dbcr->selectcol_arrayref('SELECT kwid FROM memkeyword2 WHERE userid = ? AND memid = ?',
                                           undef, $u->{userid}, $memid);
        return undef if $dbcr->err;

    } else {
        my $dbh = LJ::get_db_writer();
        $kwids = $dbh->selectcol_arrayref('SELECT kwid FROM memkeyword WHERE memid = ?', undef, $memid);
        return undef if $dbh->err;
    }

    # all good, return
    return $kwids;
}

# <LJFUNC>
# name: LJ::Memories::update_memory
# class: web
# des: Updates the description and security of a memory.
# args: uuobj, memid, updopts
# des-uuobj: User id or user object to update memory of.
# des-memid: Memory id to update.
# des-updopts: Update options, hashref with keys 'des' and 'security', values being what
#   you want to update the memory to have.
# returns: 1 on success, undef on error
# </LJFUNC>
sub update_memory {
    my ($u, $memid, $upd) = @_;
    $u = LJ::want_user($u);
    $memid += 0;
    return unless $u && $memid && %{$upd || {}};

    # get database handle
    my ($db, $table) = $u->{dversion} > 5 ?
                       (LJ::get_cluster_master($u), '2') :
                       (LJ::get_db_writer(), '');
    return undef unless $db;

    # construct update lines... only valid things we can update are des and security
    my @updates;
    foreach my $what (keys %$upd) {
        next unless $what =~ m/^(?:des|security)$/;
        push @updates, "$what=" . $db->quote($upd->{$what});
    }
    my $updstr = join ',', @updates;

    # now perform update
    $db->do("UPDATE memorable$table SET $updstr WHERE userid = ? AND memid = ?",
            undef, $u->{userid}, $memid);
    return undef if $db->err;
    return 1;
}

# this messy function gets memories based on an options hashref.  this is an
# API API and isn't recommended for use by BML etc... add to the API and have
# API functions call this if needed.
# 
# options in $opts hashref:
#   security => [ 'public', 'private', ... ], or some subset thereof
#   filter => 'all' | 'own' | 'other', filter -- defaults to all
#   notext => 1/0, if on, do not load/return description field
#   byid => [ 1, 2, 3, ... ], load memories by *memid*
#   byditemid => [ 1, 2, 3 ... ], load by ditemid (MUST specify journalid too)
#   journalid => 1, find memories by ditemid (see above) for this journalid
#
# note that all memories are loaded from a single user, specified as the first
# parameter.  does not let you load memories from more than one user.
sub _memory_getter {
    my ($u, $opts) = @_;
    $u = LJ::want_user($u);
    $opts ||= {};
    return undef unless $u;

    # various selection options
    my $secwhere = '';
    if (@{$opts->{security} || []}) {
        my @secs;
        foreach my $sec (@{$opts->{security}}) {
            push @secs, $sec
                if $sec =~ /^(?:public|friends|private)$/;
        }
        $secwhere = "AND security IN (" . join(',', map { "'$_'" } @secs) . ")";
    }
    my $extrawhere;
    if ($opts->{filter} eq 'all') { $extrawhere = ''; }
    elsif ($opts->{filter} eq 'own') { $extrawhere = "AND journalid = $u->{userid}"; }
    elsif ($opts->{filter} eq 'other') { $extrawhere = "AND journalid <> $u->{userid}"; }
    my $des = $opts->{notext} ? '' : 'des, ';
    my $selwhere;
    if (@{$opts->{byid} || []}) {
        # they want to get some explicit memories by memid
        my $in = join ',', map { $_+0 } @{$opts->{byid}};
        $selwhere = "AND memid IN ($in)";
    } elsif ($opts->{byditemid} && $opts->{journalid}) {
        # or, they want to see if a memory exists for a particular item
        my $selitemid = $u->{dversion} > 5 ? "ditemid" : "jitemid";
        $opts->{byditemid} += 0;
        $opts->{journalid} += 0;
        $selwhere = "AND journalid = $opts->{journalid} AND $selitemid = $opts->{byditemid}";
    }

    # load up memories into hashref
    my (%memories, $sth);
    if ($u->{dversion} > 5) {
        # new clustered memories
        my $dbcr = LJ::get_cluster_reader($u);
        $sth = $dbcr->prepare("SELECT memid, userid, journalid, ditemid, $des security " .
                              "FROM memorable2 WHERE userid = ? $selwhere $secwhere $extrawhere");
    } else {
        # old global memories
        my $dbr = LJ::get_db_reader();
        $sth = $dbr->prepare("SELECT memid, userid, journalid, jitemid, $des security " .
                             "FROM memorable WHERE userid = ? $selwhere $secwhere $extrawhere");
    }

    # general execution and fetching for return
    $sth->execute($u->{userid});
    return undef if $sth->err;
    while ($_ = $sth->fetchrow_hashref()) {
        # we have to do this ditemid->jitemid to make old code work,
        # but this can probably go away at some point...
        if (defined $_->{ditemid}) {
            $_->{jitemid} = $_->{ditemid};
        } else {
            $_->{ditemid} = $_->{jitemid};
        }
        $memories{$_->{memid}} = $_;
    }
    return \%memories;
}

# <LJFUNC>
# name: LJ::Memories::get_by_id
# class: web
# des: Get memories given some memory ids.
# args: uuobj, memids
# des-uuobj: User id or user object to get memories for.
# des-memids: The rest of the memory ids.  Array.  (Pass them in as individual parameters...)
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
sub get_by_id {
    my $u = shift;
    return {} unless @_; # make sure they gave us some ids

    # pass to getter to get by id
    return LJ::Memories::_memory_getter($u, { byid => [ map { $_+0 } @_ ] });
}

# <LJFUNC>
# name: LJ::Memories::get_by_ditemid
# class: web
# des: Get memory for a given journal entry.
# args: uuobj, journalid, ditemid
# des-uuobj: User id or user object to get memories for.
# des-journalid: Userid for journal entry is in.
# des-ditemid: Display itemid of entry.
# returns: Hashref of individual memory.
# </LJFUNC>
sub get_by_ditemid {
    my ($u, $jid, $ditemid) = @_;
    $jid += 0;
    $ditemid += 0;
    return undef unless $jid && $ditemid; # _memory_getter checks $u

    # pass to getter with appropriate options
    my $memhash = LJ::Memories::_memory_getter($u, { byditemid => $ditemid, journalid => $jid });
    return undef unless %{$memhash || {}};
    return [ values %$memhash ]->[0]; # ugly
}

# <LJFUNC>
# name: LJ::Memories::get_by_user
# class: web
# des: Get memories given a user.
# args: uuobj
# des-uuobj: User id or user object to get memories for.
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
sub get_by_user {
    # simply passes through to _memory_getter
    return LJ::Memories::_memory_getter(@_);
}

# <LJFUNC>
# name: LJ::Memories::get_by_keyword
# class: web
# des: Get memories given a user and a keyword/keyword id.
# args: uuobj, kwoid, opts
# des-uuobj: User id or user object to get memories for.
# des-kwoid: Keyword (string) or keyword id (number) to get memories for.
# des-opts: Hashref of extra options to pass through to memory getter.  Suggested options
#   are filter and security for limiting the memories returned.
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
sub get_by_keyword {
    my ($u, $kwoid, $opts) = @_;
    $u = LJ::want_user($u);
    my $kwid = $kwoid+0;
    my $kw = defined $kwoid && !$kwid ? $kwoid : undef;
    return undef unless $u && ($kwid || defined $kw);

    # two entirely separate codepaths, depending on the user's dversion.
    my $memids;
    if ($u->{dversion} > 5) {
        # the smart way
        my $dbcr = LJ::get_cluster_reader($u);
        return undef unless $dbcr;

        # get keyword id if we don't have it
        if (defined $kw) {
            $kwid = $dbcr->selectrow_array('SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                           undef, $u->{userid}, $kw)+0;
        }
        return undef unless $kwid;

        # now get the actual memory ids
        $memids = $dbcr->selectcol_arrayref('SELECT memid FROM memkeyword2 WHERE userid = ? AND kwid = ?',
                                           undef, $u->{userid}, $kwid);
        return undef if $dbcr->err;
    } else {
        # the dumb way
        my $dbr = LJ::get_db_reader();
        return undef unless $dbr;

        # get keyword id if we don't have it
        if (defined $kw) {
            $kwid = $dbr->selectrow_array('SELECT kwid FROM keywords WHERE keyword = ?', undef, $kw)+0;
        }
        return undef unless $kwid;

        # now get memory ids.  this has to join.  :(
        $memids = $dbr->selectcol_arrayref('SELECT m.memid FROM memorable m, memkeyword mk ' .
                                           'WHERE m.userid = ? AND mk.memid = m.memid AND mk.kwid = ?',
                                           undef, $u->{userid}, $kwid);
        return undef if $dbr->err;
    }

    # standard in both cases
    return {} unless @{$memids || []};
    return LJ::Memories::_memory_getter($u, { %{$opts || {}}, byid => $memids });
}

# <LJFUNC>
# name: LJ::Memories::get_keywords
# class:
# des: Retrieves keyword/keyids without big joins, returns a hashref.
# args: uobj
# des-uobj: User object to get keyword pairs for.
# returns: Hashref; { keywordid => keyword }
# </LJFUNC>
sub get_keywords {
    my $u = shift;
    $u = LJ::want_user($u);
    return undef unless $u;

    my $use_reader = 0;
    my $memkey = [$u->{userid},"memkwid:$u->{userid}"];
    my $ret = LJ::MemCache::get($memkey);
    return $ret if defined $ret;
    $ret = {};

    if ($u->{dversion} > 5) {
        # new style clustered code
        my $dbcm = LJ::get_cluster_def_reader($u);
        unless ($dbcm) {
            $use_reader = 1;
            $dbcm = LJ::get_cluster_reader($u);
        }
        my $ids = $dbcm->selectcol_arrayref('SELECT DISTINCT kwid FROM memkeyword2 WHERE userid = ?',
                                            undef, $u->{userid});
        if (@{$ids || []}) {
            my $in = join ",", @$ids;
            my $rows = $dbcm->selectall_arrayref('SELECT kwid, keyword FROM userkeywords ' .
                                                 "WHERE userid = ? AND kwid IN ($in)", undef, $u->{userid});
            $ret->{$_->[0]} = $_->[1] foreach @{$rows || []};
        }

    } else {
        # old style code using global
        my $dbh = LJ::get_db_writer();
        unless ($dbh) {
            $use_reader = 1;
            $dbh = LJ::get_db_reader();
        }
        my $sth = $dbh->prepare("SELECT DISTINCT mk.kwid ".
                                "FROM ".
                                "  memorable m FORCE INDEX (uniq),".
                                "  memkeyword mk ".
                                "WHERE mk.memid=m.memid AND m.userid=?");
        $sth->execute($u->{userid});
        my @ids;
        push @ids, $_ while $_ = $sth->fetchrow_array;

        if (@ids) {
            my $in = join(",", @ids);
            $sth = $dbh->prepare("SELECT kwid, keyword FROM keywords WHERE kwid IN ($in)");
            $sth->execute;

            while (my ($id,$kw) = $sth->fetchrow_array) {
                $ret->{$id} = $kw;
            }
        }
    }

    LJ::MemCache::set($memkey, $ret, 86400) unless $use_reader;
    return $ret;
}

# <LJFUNC>
# name: LJ::Memories::updated_keywords
# class: web
# des: Deletes memcached keyword data.
# args: uobj
# des-uobj: User object to clear memcached keywords for.
# returns: undef.
# </LJFUNC>
sub updated_keywords {
    my $u = shift;
    return unless ref $u;
    LJ::MemCache::delete([$u->{userid},"memkwid:$u->{userid}"]);
    return undef;
}

1;
