#!/usr/bin/perl
#

use strict;
$| = 1;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
use LJ::User;

use constant DEBUG => 0;  # turn on for debugging (mostly db handle crap)

my $BLOCK_MOVE   = 5000;  # user rows to get at a time before moving
my $BLOCK_INSERT =   25;  # rows to insert at a time when moving users
my $BLOCK_UPDATE = 1000;  # users to update at a time if they had no data to move
my $DB_MAX_TIME  =  300;  # seconds that handles should be good for (before expiring)

# used for keeping stats notes
my %stats = (); # { 'stat' => 'value' }

# database handle retrieval sub
my $dbtime; # number of times we've gotten a handle so we can make them stale
my $get_db_handles = sub {
    # figure out what cluster to load
    my $cid = shift(@_) + 0;

    # update count and end request?
    my $gotnew = 0;
    if (time() > $dbtime + $DB_MAX_TIME) {
        # if $dbtime is undef, that means this is our first time through, so nothing
        # is cached anyway, so don't call end_request, but consider them new (so we
        # set them up below)
        if ($dbtime) {
            # disconnect database handles so we have fresh ones to use
            print "DEBUG: Calling LJ::end_request to flush handles\n" if DEBUG;
            LJ::end_request();
        }
        $gotnew = 1;
        $dbtime = time();
    }

    # now get handles
    my $dbh = LJ::get_dbh({ raw => 1 }, "master");
    my $dbcm = LJ::get_cluster_master({ raw => 1 }, $cid) if $cid;

    # if we have undef, we have a problem (although, $cid == 0 makes a $dbcm undef okay)
    die "Unable to get database handles" unless $dbh && (!$cid || $dbcm);

    # update handles to raise errors and not timeout for a while
    if ($gotnew) {
        print "DEBUG: Got new database handles\n" if DEBUG;
        foreach my $db ($dbh, $dbcm) {
            next unless $db; # $dbcm might be undef
            eval {
                # in case $dbcm == $dbh, and we're on MySQL 3 and we already
                # set RaiseError on the first pass through this foreach, we
                # wrap in an eval so we don't die out
                $db->do("SET wait_timeout=28800");
            };
            $db->{'RaiseError'} = 1;
        }
    }

    # return one or both, depending on what they wanted
    return $cid ? ($dbh, $dbcm) : $dbh;
};

# percentage complete
my $status = sub {
    my ($ct, $tot, $units, $user) = @_;
    my $len = length($tot);

    my $usertxt = $user ? " Moving user: $user" : '';
    return sprintf(" \[%6.2f%%: %${len}d/%${len}d $units]$usertxt\n",
                   ($ct / $tot) * 100, $ct, $tot);
};

my $header = sub {
    my $size = 50;
    return "\n" .
           ("#" x $size) . "\n" .
           "# $_[0] " . (" " x ($size - length($_[0]) - 4)) . "#\n" .
           ("#" x $size) . "\n\n";
};

my $zeropad = sub {
    return sprintf("%d", $_[0]);
};

# mover function
my $move_user = sub {
    my $u = shift;

    # make sure our user is of the proper dversion
    return 0 unless $u->{'dversion'} == 5;

    # ignore expunged users
    if ($u->{'statusvis'} eq "X") {
        LJ::update_user($u, { dversion => 6 })
            or die "error updating dversion";
        $u->{dversion} = 6; # update local copy in memory
        return 1;
    }

    # get a handle for every user to revalidate our connection?
    my ($dbh, $dbcm) = $get_db_handles->($u->{clusterid});
    die "Unable to get database handles" unless $dbh && $dbcm && $u->writer;

    # step 1: get all friend groups and move those.  safe to just grab with no limit because
    # there are limits to how many friend groups you can have (30).
    my $rows = $dbh->selectall_arrayref('SELECT groupnum, groupname, sortorder, is_public ' .
                                        'FROM friendgroup WHERE userid = ?', undef, $u->{userid});
    if (@$rows) {
        # got some rows, create an update statement
        my (@bind, @vars);
        foreach my $row (@$rows) {
            push @bind, "($u->{userid}, ?, ?, ?, ?)";
            push @vars, $_ foreach @$row;
        }
        my $bind = join ',', @bind;
        $u->do("REPLACE INTO friendgroup2 (userid, groupnum, groupname, sortorder, is_public) " .
               "VALUES $bind", undef, @vars);
    }

    # general purpose flusher for use below
    my (@bind, @vars);
    my $flush = sub {
        return unless @bind;
        my ($table, $cols) = @_;

        # insert data into cluster master
        my $bind = join(",", @bind);
        $dbcm->do("REPLACE INTO $table ($cols) VALUES $bind", undef, @vars);
        die "error in flush $table: " . $dbcm->errstr . "\n" if $dbcm->err;

        # reset values
        @bind = ();
        @vars = ();
    };

    # step 1.5: see if the user has any data already? clear it if so.
    my $counter = $u->selectrow_array("SELECT max FROM counter WHERE journalid = ? AND area = 'R'",
                                      undef, $u->{userid});
    $counter += 0;
    if ($counter > 0) {
        # yep, so we need to delete stuff, real data first
        foreach my $table (qw(memorable2 memkeyword2 userkeywords)) {
            $u->do("DELETE FROM $table WHERE userid = ?", undef, $u->{userid});
        }

        # delete counters used (including memcache of such)
        $u->do("DELETE FROM counter WHERE journalid = ? AND area IN ('R', 'K')", undef, $u->{userid});
        LJ::MemCache::delete([$u->{userid}, "auc:$u->{userid}:R"]);
        LJ::MemCache::delete([$u->{userid}, "auc:$u->{userid}:K"]);
    }

    # step 2: get all of their memories and move them, creating the oldmemid -> newmemid mapping
    # that we can use in later steps to migrate keywords
    my %bindings; # ( oldid => newid )
    my $sth = $dbh->prepare('SELECT memid, journalid, jitemid, des, security ' .
                            'FROM memorable WHERE userid = ?');
    $sth->execute($u->{userid});
    while (my $row = $sth->fetchrow_hashref()) {
        # got a row, good
        my $newid = LJ::alloc_user_counter($u, 'R');
        $bindings{$row->{memid}} = $newid;

        # push data
        push @bind, "($u->{userid}, ?, ?, ?, ?, ?)";
        push @vars, ($newid, map { $row->{$_} } qw(journalid jitemid des security));

        # flush if necessary
        $flush->('memorable2', 'userid, memid, journalid, ditemid, des, security')
            if @bind > $BLOCK_INSERT;
    }
    $flush->('memorable2', 'userid, memid, journalid, ditemid, des, security');

    # step 3: get the list of keywords that these memories all use
    my %kwmap;
    if (%bindings) {
        my $memids = join ',', map { $_+0 } keys %bindings;
        my $rows = $dbh->selectall_arrayref("SELECT memid, kwid FROM memkeyword WHERE memid IN ($memids)");
        push @{$kwmap{$_->[1]}}, $_->[0] foreach @$rows; # kwid -> [ memid, memid, memid ... ]
    }

    # step 4: get the actual keywords associated with these keyword ids
    my %kwidmap;
    if (%kwmap) {
        my $kwids = join ',', map { $_+0 } keys %kwmap;
        my $rows = $dbh->selectall_arrayref("SELECT kwid, keyword FROM keywords WHERE kwid IN ($kwids)");
        %kwidmap = map { $_->[0] => $_->[1] } @$rows; # kwid -> keyword
    }

    # step 5: now migrate all keywords into userkeywords table
    my %mappings;
    while (my ($kwid, $keyword) = each %kwidmap) {
        # reallocate counter
        my $newkwid = LJ::alloc_user_counter($u, 'K');
        $mappings{$kwid} = $newkwid;

        # push data
        push @bind, "($u->{userid}, ?, ?)";
        push @vars, ($newkwid, $keyword);

        # flush if necessary
        $flush->('userkeywords', 'userid, kwid, keyword')
            if @bind > $BLOCK_INSERT;
    }
    $flush->('userkeywords', 'userid, kwid, keyword');

    # step 6: now we have to do some mapping conversions and put new data into memkeyword2 table
    while (my ($oldkwid, $oldmemids) = each %kwmap) {
        foreach my $oldmemid (@$oldmemids) {
            # get new data
            my ($newkwid, $newmemid) = ($mappings{$oldkwid}, $bindings{$oldmemid});

            # push data
            push @bind, "($u->{userid}, ?, ?)";
            push @vars, ($newmemid, $newkwid);

            # flush?
            $flush->('memkeyword2', 'userid, memid, kwid')
                if @bind > $BLOCK_INSERT;
        }
    }
    $flush->('memkeyword2', 'userid, memid, kwid');

    # delete memcache keys that hold old data
    LJ::MemCache::delete([$u->{userid}, "memkwid:$u->{userid}"]);

    # haven't died yet?  everything is still going okay, so update dversion
    LJ::update_user($u, { 'dversion' => 6 })
        or die "error updating dversion";
    $u->{'dversion'} = 6; # update local copy in memory

    return 1;
};

# get dbh handle
my $dbh = LJ::get_db_writer(); # just so we can get users...
die "Could not connect to global master" unless $dbh;

# get user count
my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 5");
$stats{'total_users'} = $total+0;

# print out header and total we're moving
print $header->("Moving user data");
print "Processing $stats{'total_users'} total users with the old dversion\n";

# loop until we have no more users to convert
my $ct;
while (1) {

    # get blocks of $BLOCK_MOVE users at a time
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion = 5 LIMIT $BLOCK_MOVE");
    $sth->execute();
    $ct = 0;
    my %us;
    while (my $u = $sth->fetchrow_hashref()) {
        $us{$u->{userid}} = $u;
        $ct++;
    }

    # jump out if we got nothing
    last unless $ct;

    # now that we have %us, we can see who has data
    my $ids = join ',', map { $_+0 } keys %us;
    my $has_memorable = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM memorable WHERE userid IN ($ids)");
    my $has_fgroups = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM friendgroup WHERE userid IN ($ids)");
    my %uids = ( map { $_ => 1 } (@$has_memorable, @$has_fgroups) );
    my %moved_slow;
    foreach my $id (keys %uids) {
        # this person has memories, move them the slow way
        die "Userid $id in \$has_memorable, but not in \%us...fatal error\n" unless $us{$id};
        $stats{'slow_moved'}++;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users", $us{$id}{user});

        # now move the user
        bless $us{$id}, 'LJ::User';
        $move_user->($us{$id});
        $moved_slow{$id} = 1;
    }

    # now see who we can do in a fast way
    my @fast_ids = map { $_+0 } grep { !$moved_slow{$_} } keys %us;
    if (@fast_ids) {
        # update stats for counting and print
        $stats{'fast_moved'} += @fast_ids;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users");

        # block update
        LJ::update_user(\@fast_ids, { dversion => 6 });
    }

}

# ...done?
print $header->("Dversion 5->6 conversion completed");
print "  Users moved: " . $zeropad->($stats{'slow_moved'}) . "\n";
print "Users updated: " . $zeropad->($stats{'fast_moved'}) . "\n\n";
