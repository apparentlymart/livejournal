#!/usr/bin/perl
#

use strict;
$| = 1;

use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Blob;
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
    return 0 unless $u->{'dversion'} == 6;

    # ignore expunged users
    if ($u->{'statusvis'} eq "X") {
        LJ::update_user($u, { dversion => 7 })
            or die "error updating dversion";
        $u->{dversion} = 7; # update local copy in memory
        return 1;
    }

    # get a handle for every user to revalidate our connection?
    my ($dbh, $dbcm) = $get_db_handles->($u->{clusterid});
    die "Unable to get database handles" unless $dbh && $dbcm && $u->writer;

    # step 0.5: delete all the bogus userblob rows for this user
    # This is due to the auto_increment for the blobid overflowing
    # and thus all entries recieving an id of max id for a mediumint.
    # This is lame.
    my $domainid = LJ::get_blob_domainid('userpic');
    $u->do("DELETE FROM userblob WHERE journalid=$u->{userid} AND domain=$domainid AND blobid>=16777216");
    die "error in delete: " . $u->errstr . "\n" if $u->err;

    # step 1: get all user pictures and move those.  safe to just grab with no limit
    # since users can only have a limited number of them
    my $rows = $dbh->selectall_arrayref('SELECT picid, userid, contenttype, width, height, state, picdate, md5base64 ' .
                                        'FROM userpic WHERE userid = ?', undef, $u->{userid}) || [];

    if (@$rows) {
        # got some rows, create an update statement
        my (@bind, @vars, @blobids, @blobbind, @picinfo);
        foreach my $row (@$rows) {
            my $picid = $row->[0];
            push @bind, "(?, ?, ?, ?, ?, ?, ?, ?)";

            $row->[2] = {'image/gif' => 'G',
                         'image/jpeg' => 'J',
                         'image/png' => 'P'}->{$row->[2]};
            push @vars, @$row;

            # [picid, fmt]
            my $fmt = {'G' => 'gif',
                       'J' => 'jpg',
                       'P' => 'png'}->{$row->[2]};
            push @picinfo, [$picid, $fmt];

            # picids
            push @blobids, $picid;
            push @blobbind, "?";
        }

        my $bind = join ',', @bind;
        $u->do("REPLACE INTO userpic2 (picid, userid, fmt, width, height, state, picdate, md5base64) " .
               "VALUES $bind", undef, @vars);
        die "error in userpic2 replace: " . $u->errstr . "\n" if $u->err;

        # step 1.5: insert missing rows into the userblob table
        my $blobbind = join ',', @blobbind;
        my $blobrows = $dbcm->selectall_hashref("SELECT blobid FROM userblob WHERE journalid=$u->{userid} AND domain=$domainid " .
                                                "AND blobid IN ($blobbind)", 'blobid', undef, @blobids) || {};

        my (@insertbind, @insertvars);
        foreach my $pic (@picinfo) {
            my ($picid, $fmt) = @$pic;
            unless ($blobrows->{$picid}) {
                push @insertbind, "(?, ?, ?, ?)";

                my $blob = LJ::Blob::get($u, "userpic", $fmt, $picid);
                my $length = length($blob);
                $blob = undef;

                push @insertvars, $u->{'userid'}, $domainid, $picid, $length;
            }
        }
        if (@insertbind) {
            my $insertbind = join ',', @insertbind;
            $u->do("INSERT INTO userblob (journalid, domain, blobid, length) " .
                   "VALUES $insertbind", undef, @insertvars);
            die "error in userblob insert: " . $u->errstr . "\n" if $u->err;
        }
    }

    # general purpose flusher for use below
    my (@bind, @vars);
    my $flush = sub {
        return unless @bind;
        my ($table, $cols) = @_;

        # insert data into cluster master
        my $bind = join(",", @bind);
        $u->do("REPLACE INTO $table ($cols) VALUES $bind", undef, @vars);
        die "error in flush $table: " . $u->errstr . "\n" if $u->err;

        # reset values
        @bind = ();
        @vars = ();
    };

    # step 2: get the mapping of all of their keywords
    my $kwrows = $dbh->selectall_arrayref('SELECT picid, kwid FROM userpicmap WHERE userid=?',
                                          undef, $u->{'userid'});
    my %kwmap;
    if (@$kwrows) {
        push @{$kwmap{$_->[1]}}, $_->[0] foreach @$kwrows; # kwid -> [ picid, picid, picid ... ]
    }

    # step 3: get the actual keywords associated with these keyword ids
    my %kwidmap;
    if (%kwmap) {
        my $kwids = join ',', map { $_+0 } keys %kwmap;
        my $rows = $dbh->selectall_arrayref("SELECT kwid, keyword FROM keywords WHERE kwid IN ($kwids)");
        %kwidmap = map { $_->[0] => $_->[1] } @$rows; # kwid -> keyword
    }

    # step 4: now migrate all keywords into userkeywords table
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

    # step 5: now we have to do some mapping conversions and put new data into userpicmap2 table
    while (my ($oldkwid, $picids) = each %kwmap) {
        foreach my $picid (@$picids) {
            # get new data
            my $newkwid = $mappings{$oldkwid};

            # push data
            push @bind, "($u->{userid}, ?, ?)";
            push @vars, ($picid, $newkwid);

            # flush?
            $flush->('userpicmap2', 'userid, picid, kwid')
                if @bind > $BLOCK_INSERT;
        }
    }
    $flush->('userpicmap2', 'userid, picid, kwid');

    # delete memcache keys that hold old data
    LJ::MemCache::delete([$u->{userid}, "upicinf:$u->{userid}"]);

    # haven't died yet?  everything is still going okay, so update dversion
    LJ::update_user($u, { 'dversion' => 7 })
        or die "error updating dversion";
    $u->{'dversion'} = 7; # update local copy in memory

    return 1;
};

# get dbh handle
my $dbh = LJ::get_db_writer(); # just so we can get users...
die "Could not connect to global master" unless $dbh;

# get user count
my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 6");
$stats{'total_users'} = $total+0;

# print out header and total we're moving
print $header->("Moving user data");
print "Processing $stats{'total_users'} total users with the old dversion\n";

# loop until we have no more users to convert
my $ct;
while (1) {

    # get blocks of $BLOCK_MOVE users at a time
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion = 6 LIMIT $BLOCK_MOVE");
    $sth->execute();
    $ct = 0;
    my (%us, %fast);
    while (my $u = $sth->fetchrow_hashref()) {
        $us{$u->{userid}} = $u;
        $fast{$u->{userid}} = 1;
        $ct++;
    }

    # jump out if we got nothing
    last unless $ct;

    # now that we have %us, we can see who has data
    my $ids = join ',', map { $_+0 } keys %us;
    my $has_upics = $dbh->selectcol_arrayref("SELECT DISTINCT userid FROM userpic WHERE userid IN ($ids)");
    my %uids = ( map { $_ => 1 } (@$has_upics) );

    # remove folks that have userpics from the fast list
    delete $fast{$_} foreach keys %uids;

    # now see who we can do in a fast way
    my @fast_ids = map { $_+0 } keys %fast;
    if (@fast_ids) {
        # update stats for counting and print
        $stats{'fast_moved'} += @fast_ids;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users");

        # block update
        LJ::update_user(\@fast_ids, { dversion => 7 });
    }
    
    my $slow_todo = scalar keys %uids;
    print "Of $BLOCK_MOVE, $slow_todo have to be slow-converted...\n";
    foreach my $id (keys %uids) {
        # this person has userpics, move them the slow way
        die "Userid $id in \$has_upics, but not in \%us...fatal error\n" unless $us{$id};
        $stats{'slow_moved'}++;
        print $status->($stats{'slow_moved'}+$stats{'fast_moved'}, $stats{'total_users'}, "users", $us{$id}{user});

        # now move the user
        bless $us{$id}, 'LJ::User';
        $move_user->($us{$id});
    }

}

# ...done?
print $header->("Dversion 6->7 conversion completed");
print "  Users moved: " . $zeropad->($stats{'slow_moved'}) . "\n";
print "Users updated: " . $zeropad->($stats{'fast_moved'}) . "\n\n";
