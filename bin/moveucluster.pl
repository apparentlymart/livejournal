#!/usr/bin/perl
#
# Moves a user between clusters.
#

use strict;
use Getopt::Long;

my $opt_del = 0;
exit 1 unless GetOptions('delete' => \$opt_del);

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh("master");

my $user = shift @ARGV;
my $dclust = shift @ARGV;

sub usage {
    die "Usage:\n  movecluster.pl <user> <destination cluster #>\n";
}

usage() unless defined $user;
usage() unless defined $dclust;

my $u = LJ::load_user($dbh, $user);
die "Non-existent user $user.\n" unless $u;

die "Can't move back to legacy cluster 0\n" unless $dclust;

my $dbch = LJ::get_dbh("cluster$dclust");
die "Undefined or down cluster \#$dclust\n" unless $dbch;

my $separate_cluster = LJ::use_diff_db("master", "cluster$dclust");

$dbh->{'RaiseError'} = 1;
$dbch->{'RaiseError'} = 1;

my $sclust = $u->{'clusterid'};

if ($sclust == $dclust) {
    die "User '$user' is already on cluster $dclust\n";
}

if ($sclust) {
    # TODO: intra-cluster moving we can deal with later.
    die "Moving between clusters isn't yet supported; only from cluster 0 to somewhere else.\n";
}

my $userid = $u->{'userid'};

my $recentpoint;
if ($LJ::USE_RECENT_TABLES) {
    $recentpoint = $dbh->selectrow_array("SELECT DATE_SUB(NOW(), INTERVAL $LJ::RECENT_DAYS DAY)");
}

# find readonly cap class, complain if not found
my $readonly_bit = undef;
foreach (keys %LJ::CAP) {
    if ($LJ::CAP{$_}->{'_name'} eq "_moveinprogress" &&
        $LJ::CAP{$_}->{'readonly'} == 1) {
        $readonly_bit = $_;
        last;
    }
}
unless (defined $readonly_bit) {
    die "Won't move user without %LJ::CAP capability class named '_moveinprogress' with readonly => 1\n";
}

# make sure a move isn't already in progress
if (($u->{'caps'}+0) & (1 << $readonly_bit)) {
    die "User '$user' is already in the process of being moved?\n";
}


print "Moving '$u->{'user'}' from cluster $sclust to $dclust:\n";

# set readonly cap bit on user
$dbh->do("UPDATE user SET caps=caps|(1<<$readonly_bit) WHERE userid=$userid");

# wait a bit for writes to stop if journal is somewhat active (last week update)
my $secidle = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()-UNIX_TIMESTAMP(timeupdate) ".
                                    "FROM userusage WHERE userid=$userid");
sleep(3) unless $secidle > 86400*7;

my $last = time();
my $stmsg = sub {
    my $msg = shift;
    my $now = time();
    return if ($now < $last + 1);
    $last = $now;
    print $msg;
};

my %bufcols = ();  # db|table -> scalar "(foo, anothercol, lastcol)" or undef or ""
my %bufrows = ();  # db|table -> [ []+ ]
my %bufdbmap = (); # scalar(DBI hashref) -> DBI hashref

my $flush_buffer = sub {
    my $dbandtable = shift;
    my ($db, $table) = split(/\|/, $dbandtable);
    $db = $bufdbmap{$db};
    return unless exists $bufcols{$dbandtable};
    my $sql = "REPLACE INTO $table $bufcols{$dbandtable} VALUES ";
    $sql .= join(", ",
                 map { my $r = $_;
                       "(" . join(", ",
                                  map { $db->quote($_) } @$r) . ")" }
                 @{$bufrows{$dbandtable}});
    $db->do($sql);
    delete $bufrows{$dbandtable};
    delete $bufcols{$dbandtable};
};

my $flush_all = sub {
    foreach (keys %bufcols) {
        $flush_buffer->($_);
    }
};

my $replace_into = sub {
    my $db = ref $_[0] ? shift : $dbch;  # optional first arg
    my ($table, $cols, $max, @vals) = @_;
    my $dbandtable = scalar($db) . "|$table";
    $bufdbmap{$db} = $db;
    if (exists $bufcols{$dbandtable} && $bufcols{$dbandtable} ne $cols) {
        $flush_buffer->($dbandtable);
    }
    $bufcols{$dbandtable} = $cols;
    push @{$bufrows{$dbandtable}}, [ @vals ];

    if (scalar @{$bufrows{$dbandtable}} > $max) {
        $flush_buffer->($dbandtable);
    }
};

my $bufread;

if ($sclust == 0)
{
    # do bio stuff
    {
        my $bio = $dbh->selectrow_array("SELECT bio FROM userbio WHERE userid=$userid");
        my $bytes = length($bio);
        $dbch->do("REPLACE INTO dudata (userid, area, areaid, bytes) VALUES ($userid, 'B', 0, $bytes)");
        if ($separate_cluster) {
            $bio = $dbh->quote($bio);
            $dbch->do("REPLACE INTO userbio (userid, bio) VALUES ($userid, $bio)");
        }
    }

    my @itemids = reverse @{$dbh->selectcol_arrayref("SELECT itemid FROM log ".
                                                     "WHERE ownerid=$u->{'userid'} ".
                                                     "ORDER BY ownerid, rlogtime")};

    $bufread = make_buffer_reader("itemid", \@itemids);

    my $todo = @itemids;
    my $done = 0;
    my $stime = time();
    print "Total: $todo\n";

    # moving time, journal item at a time, and everything recursively under it
    foreach my $itemid (@itemids) {
        movefrom0_logitem($itemid);
        $done++;
        my $percent = $done/$todo;
        my $elapsed = time() - $stime;
        my $totaltime = $elapsed * (1 / $percent);
        my $timeremain = int($totaltime - $elapsed);
        $stmsg->(sprintf "$user: copy $done/$todo (%.2f%%) +${elapsed}s -${timeremain}s\n", 100*$percent);
    }

    $flush_all->();

    # update their memories.  in particular, any memories of their own
    # posts need to to be updated from the (0, globalid) to
    # (journalid, jitemid) format, to make the memory filter feature
    # work.  (it checks the first 4 bytes only, not joining the
    # globalid on the clustered log table)
    print "Fixing memories.\n";
    my @fix = @{$dbh->selectall_arrayref("SELECT m.memid, o.newid FROM memorable m, oldids o WHERE ".
                                         "m.userid=$u->{'userid'} AND m.journalid=0 AND o.area='L' ".
                                         "AND o.userid=$u->{'userid'} AND m.jitemid=o.oldid")};
    foreach my $f (@fix) {
        my ($memid, $newid) = ($f->[0], $f->[1]);
        my ($newid2, $anum) = $dbch->selectrow_array("SELECT jitemid, anum FROM log2 ".
                                                     "WHERE journalid=$u->{'userid'} AND ".
                                                     "jitemid=$newid");
        if ($newid2 == $newid) {
            my $ditemid = $newid * 256 + $anum;
            print "UPDATE $memid TO $ditemid\n";
            $dbh->do("UPDATE memorable SET journalid=$u->{'userid'}, jitemid=$ditemid ".
                     "WHERE memid=$memid");
        }
    }

    # fix polls
    print "Fixing polls.\n";
    @fix = @{$dbh->selectall_arrayref("SELECT p.pollid, o.newid FROM poll p, oldids o ".
                                      "WHERE o.userid=$u->{'userid'} AND ".
                                      "o.area='L' AND o.oldid=p.itemid AND ".
                                      "p.journalid=$u->{'userid'}")};
    foreach my $f (@fix) {
        my ($pollid, $newid) = ($f->[0], $f->[1]);
        my ($newid2, $anum) = $dbch->selectrow_array("SELECT jitemid, anum FROM log2 ".
                                                     "WHERE journalid=$u->{'userid'} AND ".
                                                     "jitemid=$newid");
        if ($newid2 == $newid) {
            my $ditemid = $newid * 256 + $anum;
            print "UPDATE $pollid TO $ditemid\n";
            $dbh->do("UPDATE poll SET itemid=$ditemid WHERE pollid=$pollid");
        }
    }

    # move userpics
    print "Copying over userpics.\n";
    my @pics = @{$dbh->selectcol_arrayref("SELECT picid FROM userpic WHERE ".
                                          "userid=$u->{'userid'}")};
    foreach my $picid (@pics) {
        print "  picid\#$picid...\n";
        my $imagedata = $dbh->selectrow_array("SELECT imagedata FROM userpicblob ".
                                              "WHERE picid=$picid");
        $imagedata = $dbh->quote($imagedata);
        $dbch->do("REPLACE INTO userpicblob2 (userid, picid, imagedata) VALUES ".
                  "($u->{'userid'}, $picid, $imagedata)");
    }

    # before we start deleting, record they've moved servers.
    $dbh->do("UPDATE user SET dversion=2, clusterid=$dclust WHERE userid=$userid");
    $dbh->do("UPDATE userusage SET lastitemid=0 WHERE userid=$userid");

    # if everything's good (nothing's died yet), then delete all from source
    if ($opt_del)
    {
        $done = 0;
        $stime = time();
        foreach my $itemid (@itemids) {
            deletefrom0_logitem($itemid);
            $done++;
            my $percent = $done/$todo;
            my $elapsed = time() - $stime;
            my $totaltime = $elapsed * (1 / $percent);
            my $timeremain = int($totaltime - $elapsed);
            $stmsg->(sprintf "$user: delete $done/$todo (%.2f%%) +${elapsed}s -${timeremain}s\n", 100*$percent);
        }

        # delete bio from source, if necessary
        if ($separate_cluster) {
            $dbh->do("DELETE FROM userbio WHERE userid=$userid");
        }

        # delete source userpics
        print "Deleting cluster0 userpics...\n";
        foreach my $picid (@pics) {
            print "  picid\#$picid...\n";
            $dbh->do("DELETE FROM userpicblob WHERE picid=$picid");
        }
    }

    # unset read-only bit (marks the move is complete, also, and not aborted mid-delete)
    $dbh->do("UPDATE user SET caps=caps&~(1<<$readonly_bit) WHERE userid=$userid");

}

sub deletefrom0_logitem
{
    my $itemid = shift;

    # delete all the comments
    my $talkids = $dbh->selectcol_arrayref("SELECT talkid FROM talk ".
                                           "WHERE nodetype='L' AND nodeid=$itemid");

    my $talkidin = join(",", @$talkids);
    if ($talkidin) {
        foreach my $table (qw(talktext talkprop talk)) {
            $dbh->do("DELETE FROM $table WHERE talkid IN ($talkidin)");
        }
    }

    $dbh->do("DELETE FROM logsec WHERE ownerid=$userid AND itemid=$itemid");
    foreach my $table (qw(logprop logtext logsubject log)) {
        $dbh->do("DELETE FROM $table WHERE itemid=$itemid");
    }

    $dbh->do("DELETE FROM syncupdates WHERE userid=$userid AND nodetype='L' AND nodeid=$itemid");
}


sub movefrom0_logitem
{
    my $itemid = shift;

    my $item = $bufread->(100, "SELECT * FROM log", $itemid);
    my $itemtext = $bufread->(50, "SELECT itemid, subject, event FROM logtext", $itemid);
    return 1 unless $item && $itemtext;   # however that could happen.

    # we need to allocate a new jitemid (journal-specific itemid) for this item now.
    $dbh->{'RaiseError'} = 0;
    $dbh->do("INSERT INTO oldids (area, oldid, userid, newid) ".
             "VALUES ('L', $itemid, $userid, NULL)");
    my $jitemid = 0;
    if ($dbh->err) {
        $jitemid = $dbh->selectrow_array("SELECT newid FROM oldids WHERE area='L' AND oldid=$itemid");
    } else {
        $jitemid = $dbh->{'mysql_insertid'};
    }
    unless ($jitemid) {
        die "ERROR: could not allocate a new jitemid\n";
    }
    $dbh->{'RaiseError'} = 1;
    $item->{'jitemid'} = $jitemid;
    $item->{'anum'} = int(rand(256));

    # copy item over:
    $replace_into->("log2", "(journalid, jitemid, posterid, eventtime, logtime, ".
                    "compressed, security, allowmask, replycount, year, month, day, ".
                    "rlogtime, revttime, anum)",
                    50, map { $item->{$_} } qw(ownerid jitemid posterid eventtime
                                               logtime compressed security allowmask replycount
                                               year month day rlogtime revttime anum));

    $replace_into->("logtext2", "(journalid, jitemid, subject, event)", 10,
                    $userid, $jitemid, map { $itemtext->{$_} } qw(subject event));

    $replace_into->("logsubject2", "(journalid, jitemid, subject)", 50,
                    $userid, $jitemid, $itemtext->{'subject'});

    # add disk usage info!  (this wasn't in cluster0 anywhere)
    my $bytes = length($itemtext->{'event'}) + length($itemtext->{'subject'});
    $replace_into->("dudata", "(userid, area, areaid, bytes)", 50, $userid, 'L', $jitemid, $bytes);

    # is it in recent_?
    if ($recentpoint && $item->{'logtime'} gt $recentpoint) {
        $replace_into->("recent_logtext2", "(journalid, jitemid, logtime, subject, event)", 10,
                        $userid, $jitemid, $item->{'logtime'}, map { $itemtext->{$_} } qw(subject event));
    }

    # add the logsec item, if necessary:
    if ($item->{'security'} ne "public") {
        $replace_into->("logsec2", "(journalid, jitemid, allowmask)", 50,
                        map { $item->{$_} } qw(ownerid jitemid allowmask));
    }

    # copy its logprop over:
    while (my $lp = $bufread->(50, "SELECT itemid, propid, value FROM logprop", $itemid)) {
        next unless $lp->{'value'};
        $replace_into->("logprop2", "(journalid, jitemid, propid, value)", 50,
                        $userid, $jitemid, $lp->{'propid'}, $lp->{'value'});
    }

    # copy its syncitems over (always type 'create', since a new id)
    $replace_into->("syncupdates2", "(userid, atime, nodetype, nodeid, atype)", 50,
                    $userid, $item->{'logtime'}, 'L', $jitemid, 'create');


    # now we're done for non-commented posts
    return unless $item->{'replycount'};

    # copy its talk shit over:
    my %newtalkids = (0 => 0);  # 0 maps back to 0 still
    my $talkids = $dbh->selectcol_arrayref("SELECT talkid FROM talk ".
                                           "WHERE nodetype='L' AND nodeid=$itemid");
    my @talkids = sort { $a <=> $b } @$talkids;
    my $treader = make_buffer_reader("talkid", \@talkids);
    foreach my $t (@talkids) {
        movefrom0_talkitem($t, $jitemid, \%newtalkids, $item, $treader);
    }
}

sub movefrom0_talkitem
{
    my $talkid = shift;
    my $jitemid = shift;
    my $newtalkids = shift;
    my $logitem = shift;
    my $treader = shift;

    my $item = $treader->(100, "SELECT *, UNIX_TIMESTAMP(datepost) AS 'datepostunix' FROM talk", $talkid);
    my $itemtext = $treader->(50, "SELECT talkid, subject, body FROM talktext", $talkid);
    return 1 unless $item && $itemtext;   # however that could happen.

    # abort if this is a stranded entry.  (shouldn't happen, anyway.  even if it does, it's 
    # not like we're losing data:  the UI (talkread.bml) won't show it anyway)
    return unless defined $newtalkids->{$item->{'parenttalkid'}};

    # we need to allocate a new jitemid (journal-specific itemid) for this item now.
    $dbh->{'RaiseError'} = 0;
    $dbh->do("INSERT INTO oldids (area, oldid, userid, newid) ".
             "VALUES ('T', $talkid, $userid, NULL)");
    my $jtalkid = 0;
    if ($dbh->err) {
        $jtalkid = $dbh->selectrow_array("SELECT newid FROM oldids WHERE area='T' AND oldid=$talkid");
    } else {
        $jtalkid = $dbh->{'mysql_insertid'};
    }
    unless ($jtalkid) {
        die "ERROR: could not allocate a new jtalkid\n";
    }
    $newtalkids->{$talkid} = $jtalkid;
    $dbh->{'RaiseError'} = 1;

    # copy item over:
    $replace_into->("talk2", "(journalid, jtalkid, parenttalkid, nodeid, ".
                    "nodetype, posterid, datepost, state)", 50,
                    $userid, $jtalkid, $newtalkids->{$item->{'parenttalkid'}},
                    $jitemid, 'L',  map { $item->{$_} } qw(posterid datepost state));


    $replace_into->("talktext2", "(journalid, jtalkid, subject, body)",
                    20, $userid, $jtalkid, map { $itemtext->{$_} } qw(subject body));

    # add disk usage info!  (this wasn't in cluster0 anywhere)
    my $bytes = length($itemtext->{'body'}) + length($itemtext->{'subject'});
    $replace_into->("dudata", "(userid, area, areaid, bytes)", 50,
                    $userid, 'T', $jtalkid, $bytes);

    # is it in recent_?
    if ($recentpoint && $item->{'datepost'} gt $recentpoint) {
        $replace_into->("recent_talktext2", "(journalid, jtalkid, datepost, subject, body)",
                        20, $userid, $jtalkid, $item->{'datepost'}, 
                        map { $itemtext->{$_} } qw(subject body));
    }

    # copy its logprop over:
    while (my $lp = $treader->(50, "SELECT talkid, tpropid, value FROM talkprop", $talkid)) {
        next unless $lp->{'value'};
        $replace_into->("talkprop2", "(journalid, jtalkid, tpropid, value)", 50,
                        $userid, $jtalkid, $lp->{'tpropid'}, $lp->{'value'});
    }

    # note that poster commented here
    if ($item->{'posterid'}) {
        my $pub = $logitem->{'security'} eq "public" ? 1 : 0;
        my ($table, $db) = ("talkleft_xfp", $dbh);
        ($table, $db) = ("talkleft", $dbch) if $userid == $item->{'posterid'};
        $replace_into->($db, $table, "(userid, posttime, journalid, nodetype, ".
                        "nodeid, jtalkid, publicitem)", 50,
                        $userid, $item->{'datepostunix'}, $userid,
                        'L', $jitemid, $jtalkid, $pub);
    }
}

sub make_buffer_reader
{
    my $pricol = shift;
    my $valsref = shift;

    my %bfd;  # buffer read data.  halfquery -> { 'rows' => { id => [] },
              #                                   'remain' => [], 'loaded' => { id => 1 } }
    return sub
    {
        my ($amt, $hq, $pid) = @_;
        if (not defined $bfd{$hq}->{'loaded'}->{$pid})
        {
            if (not exists $bfd{$hq}->{'remain'}) {
                $bfd{$hq}->{'remain'} = [ @$valsref ];
            }

            my @todo;
            for (1..$amt) {
                next unless @{$bfd{$hq}->{'remain'}};
                my $id = shift @{$bfd{$hq}->{'remain'}};
                push @todo, $id;
                $bfd{$hq}->{'loaded'}->{$id} = 1;
            }

            if (@todo) {
                my $sql = "$hq WHERE $pricol IN (" . join(",", @todo) . ")";
                my $sth = $dbh->prepare($sql);
                $sth->execute;
                while (my $r = $sth->fetchrow_hashref) {
                    push @{$bfd{$hq}->{'rows'}->{$r->{$pricol}}}, $r;
                }
            }
        }

        return shift @{$bfd{$hq}->{'rows'}->{$pid}};
    };
}

1; # return true;

