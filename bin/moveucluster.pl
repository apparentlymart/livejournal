#!/usr/bin/perl
#
# Moves a user between clusters.
#

use strict;
use Getopt::Long;

my $opt_del = 0;
my $opt_destdel = 0;

my $opt_verbose = 1;
my $opt_movemaster = 0;
my $opt_prelocked = 0;
my $opt_expungedel = 0;
my $opt_ignorebit = 0;
my $opt_verify = 0;
exit 1 unless GetOptions('delete' => \$opt_del,
                         'destdelete' => \$opt_destdel,
			 'verbose=i' => \$opt_verbose,
			 'movemaster|mm' => \$opt_movemaster,
                         'prelocked' => \$opt_prelocked,
			 'expungedel' => \$opt_expungedel,
			 'ignorebit' => \$opt_ignorebit,
			 'verify' => \$opt_verify,  # slow verification pass (just for debug)
                         );
my $optv = $opt_verbose;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh({raw=>1}, "master");
die "No master db available.\n" unless $dbh;
$dbh->do("SET wait_timeout=28800");

my $user = LJ::canonical_username(shift @ARGV);
my $dclust = shift @ARGV;

sub usage {
    die "Usage:\n  movecluster.pl <user> <destination cluster #>\n";
}

# check arguments
usage() unless defined $user && defined $dclust;

# get lock
die "Failed to get move lock.\n"
    unless $dbh->selectrow_array("SELECT GET_LOCK('moveucluster-$user', 10)");

# get the user
my $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE user=?", undef, $user);
die "Non-existent user $user.\n" unless $u;

# get the destination DB handle, with a long timeout
my $dbch = LJ::get_cluster_master({raw=>1}, $dclust);
die "Undefined or down cluster \#$dclust\n" unless $dbch;
$dbch->do("SET wait_timeout=28800");

# make sure any error is a fatal error.  no silent mistakes.
$dbh->{'RaiseError'} = 1;
$dbch->{'RaiseError'} = 1;

# we can't move to the same cluster
my $sclust = $u->{'clusterid'};
if ($sclust == $dclust) {
    die "User '$user' is already on cluster $dclust\n";
}

# we don't support "cluster 0" (the really old format)
die "This mover tool doesn't support moving from cluster 0.\n" unless $sclust;
die "Can't move back to legacy cluster 0\n" unless $dclust;

# original cluster db handle.
my $dbo;
my $is_movemaster;

if ($sclust) {
    if ($opt_movemaster) {
        $dbo = LJ::get_dbh({raw=>1}, "cluster$u->{clusterid}movemaster");
        if ($dbo) {
            my $ss = $dbo->selectrow_hashref("show slave status");
            die "Move master not a slave?" unless $ss;
        }
        $is_movemaster = 1;
    }
    $dbo ||= LJ::get_cluster_master({raw=>1}, $u);
    die "Can't get source cluster handle.\n" unless $dbo;
    $dbo->{'RaiseError'} = 1;
    $dbo->do("SET wait_timeout=28800");
}

my $userid = $u->{'userid'};

# load the info on how we'll move each table.  this might die (if new tables
# with bizarre layouts are added which this thing can't auto-detect) so want
# to do it early.
my $tinfo;   # hashref of $table -> {
             #   'idx' => $index_name   # which we'll be using to iterate over
             #   'idxcol' => $col_name  # first part of index
             #   'cols' => [ $col1, $col2, ]
             #   'pripos' => $idxcol_pos,   # what field in 'cols' is $col_name
             #   'verifykey' => $col        # key used in the debug --verify pass
             # }
$tinfo = fetch_tableinfo();


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
if ($opt_prelocked) {
    unless (($u->{'caps'}+0) & (1 << $readonly_bit)) {
        die "User '$user' should have been prelocked.\n";
    }
} else {
    if (($u->{'caps'}+0) & (1 << $readonly_bit)) {
        die "User '$user' is already in the process of being moved? (cap bit $readonly_bit set)\n"
            unless $opt_ignorebit;
    }
}

if ($opt_expungedel && $u->{'statusvis'} eq "D" &&
    LJ::mysqldate_to_time($u->{'statusvisdate'}) < time() - 86400*31) {

    print "Expunging user '$u->{'user'}'\n";
    $dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart, timedone) ".
	     "VALUES (?,?,?,UNIX_TIMESTAMP(),UNIX_TIMESTAMP())", undef, 
	     $userid, $sclust, 0);
    LJ::update_user($userid, { clusterid => 0,
                               statusvis => 'X',
			       raw => "caps=caps&~(1<<$readonly_bit), statusvisdate=NOW()" });
    exit 0;
}

print "Moving '$u->{'user'}' from cluster $sclust to $dclust\n" if $optv >= 1;

# mark that we're starting the move
$dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart) ".
         "VALUES (?,?,?,UNIX_TIMESTAMP())", undef, $userid, $sclust, $dclust);
my $cmid = $dbh->{'mysql_insertid'};

# set readonly cap bit on user
unless ($opt_prelocked || 
	LJ::update_user($userid, { raw => "caps=caps|(1<<$readonly_bit)" })) 
{
    die "Failed to set readonly bit on user: $user\n";
}
$dbh->do("SELECT RELEASE_LOCK('moveucluster-$user')");

unless ($opt_prelocked) {
# wait a bit for writes to stop if journal is somewhat active (last week update)
    my $secidle = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()-UNIX_TIMESTAMP(timeupdate) ".
                                        "FROM userusage WHERE userid=$userid");
    if ($secidle) {
        sleep(2) unless $secidle > 86400*7;
        sleep(1) unless $secidle > 86400;
    }
}


if ($is_movemaster) {
    my $diff = 999_999;
    my $tries = 0;
    while ($diff > 50_000) {
        my $ss = $dbo->selectrow_hashref("show slave status");
        $tries++;
        if ($ss->{'Slave_IO_Running'} eq "Yes" && $ss->{'Slave_SQL_Running'} eq "Yes") {
            if ($ss->{'Master_Log_File'} eq $ss->{'Relay_Master_Log_File'}) {
                $diff = $ss->{'Read_Master_Log_Pos'} - $ss->{'Exec_master_log_pos'};
                print "  diff: $diff\n" if $optv >= 1;
            } else {
                print "  (Wrong log file):  $ss->{'Relay_Master_Log_File'}($ss->{'Exec_master_log_pos'}) not $ss->{'Master_Log_File'}($ss->{'Read_Master_Log_Pos'})\n" if $optv >= 1;
            }
        } else {
            die "Movemaster slave not running";
        }
    }
}


print "Moving away from cluster $sclust\n" if $optv;

while (my $cmd = $dbo->selectrow_array("SELECT cmd FROM cmdbuffer WHERE journalid=$userid")) {
    my $dbcm = LJ::get_cluster_master($sclust);
    print "Flushing cmdbuffer for cmd: $cmd\n" if $optv > 1;
    LJ::cmd_buffer_flush($dbh, $dbcm, $cmd, $userid);
}


# setup dependencies (we can skip work by not checking a table if we know 
# its dependent table was empty).  then we have to order things so deps get
# processed first.
my %was_empty;  # $table -> bool, table was found empty
my %dep = (
           "logtext2" => "log2",
           "logprop2" => "log2",
           "logsec2" => "log2",
           "talkprop2" => "talk2",
           "talktext2" => "talk2",
           "phoneposttrans" => "phonepostentry", # FIXME: ljcom
           "modblob" => "modlog",
           "sessions_data" => "sessions",
           );

# all tables we could be moving.  we need to sort them in
# order so that we check dependant tables first
my @alltables = (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL);
my @tables;
push @tables, grep { ! $dep{$_} } @alltables;
push @tables, grep { $dep{$_} } @alltables;


# these are ephemeral or handled elsewhere
my %skip_table = (
                  "cmdbuffer" => 1,       # pre-flushed
                  "events" => 1,          # handled by qbufferd (not yet used)
                  "s1stylecache" => 1,    # will be recreated
                  "captcha_session" => 1, # temporary
                  );

# we had a concern at the time of writing this dependency optization
# that we might use "log3" and "talk3" tables in the future with the
# old talktext2/etc tables.  if that happens and we forget about this,
# this code will trip it up and make us remember:
if (grep { $_ eq "log3" || $_ eq "talk3" } @tables) {
    die "This script needs updating.\n";
}


# check if dest has existing data for this user.  (but only check a few key tables)
# if anything else happens to have data, we'll just fail later.  but unlikely.
print "Checking for existing data on target cluster...\n" if $optv > 1;
foreach my $table (qw(userbio talkleft log2 talk2 sessions userproplite2)) {
    my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";

    eval { $dbch->do("HANDLER $table OPEN"); };
    if ($@) {
	die "This mover currently only works on MyISAM tables on MySQL 4.x and above.\n" .
	    "Support for InnoDB tables coming later.\n\nActual error: " .
	    $@;
    }

    my $idx = $ti->{idx};
    my $is_there = $dbch->selectrow_array("HANDLER $table READ `$idx` = ($userid) LIMIT 1");
    $dbch->do("HANDLER $table CLOSE");
    next unless $is_there;

    if ($opt_destdel) {
        foreach my $table (@tables) {
            # these are ephemeral or handled elsewhere
            next if $skip_table{$table};
            my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";
            my $pri = $ti->{idxcol};
            while ($dbch->do("DELETE FROM $table WHERE $pri=$userid LIMIT 500") > 0) {
                print "  deleted from $table\n" if $optv;
            }
        }
        last;
    } else {
	die "  Existing data on destination cluster\n";
    }
}

# start copying from source to dest.
my $rows = 0;
my @to_delete;  # array of [ $table, $prikey ]
my @styleids;   # to delete, potentially

foreach my $table (@tables) {
    next if $skip_table{$table};

    # people accounts don't have moderated posts
    next if $u->{'journaltype'} eq "P" && ($table eq "modlog" ||
					   $table eq "modblob");

    # don't waste time looking at dependent tables with empty parents
    next if $dep{$table} && $was_empty{$dep{$table}};

    my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";
    my $idx = $ti->{idx};
    my $idxcol = $ti->{idxcol};
    my $cols = $ti->{cols};
    my $pripos = $ti->{pripos};

    eval { $dbo->do("HANDLER $table OPEN"); };
    if ($@) {
	die "This mover currently only works on MyISAM tables on MySQL 4.x and above.\n".
	    "Support for InnoDB tables coming later.\n\nERROR: " .
	    $@;
    }

    my $tct = 0;            # total rows read for this table so far.
    my $hit_otheruser = 0;  # bool, set to true when we encounter data from a different userid
    my $batch_size = 1000;
    my $ct = 0;             # rows read in latest batch
    my $did_start = 0;      # bool, if process has started yet (used to enter loop, and control initial HANDLER commands)
    my $pushed_delete = 0;  # bool, if we've pushed this table on the delete list (once we find it has something)

    my $sqlins = "";
    my $sqlvals = 0;
    my $flush = sub {
	return unless $sqlins;
        print "# Flushing $table ($sqlvals recs, ", length($sqlins), " bytes)\n" if $optv;
	$dbch->do($sqlins);
	$sqlins = "";
	$sqlvals = 0;
    };

    my $insert = sub {
	my $r = shift;

	# now that we know it has something to delete (many tables are empty for users)
	unless ($pushed_delete++) {
	    push @to_delete, [ $table, $idxcol ];
	}

	if ($sqlins) {
	    $sqlins .= ", ";
	} else {
	    $sqlins = "INSERT INTO $table (" . join(', ', @{$cols}) . ") VALUES ";
	}
	$sqlins .= "(" . join(", ", map { $dbo->quote($_) } @$r) . ")";

	$sqlvals++;
	$flush->() if $sqlvals > 5000 || length($sqlins) > 800_000;
    };

    # let tables perform extra processing on the $r before it's 
    # sent off for inserting.
    my $magic;

    # we know how to compress these two tables (currently the only two)
    if ($table eq "logtext2" || $table eq "talktext2") {
	$magic = sub {
	    my $r = shift;
	    return unless length($r->[3]) > 200;
	    LJ::text_compress(\$r->[3]);
	};
    }
    if ($table eq "s1style") {
	$magic = sub {
	    my $r = shift;
	    push @styleids, $r->[0];
	};
    }

    while (! $hit_otheruser && ($ct == $batch_size || ! $did_start)) {
	my $qry = "HANDLER $table READ `$idx` NEXT LIMIT $batch_size";
	unless ($did_start) {
	    $qry = "HANDLER $table READ `$idx` = ($userid) LIMIT $batch_size";
	    $did_start = 1;
	}

	my $sth = $dbo->prepare($qry);
	$sth->{'mysql_use_result'} = 1;
	$sth->execute;

	$ct = 0;
	while (my $r = $sth->fetchrow_arrayref) {
	    if ($r->[$pripos] != $userid) {
		$hit_otheruser = 1;
		last;
	    }
	    $magic->($r) if $magic;
	    $insert->($r);
	    $tct++;
	    $ct++;
	}
    }
    $flush->();

    $dbo->do("HANDLER $table CLOSE");

    # verify the important tables
    if ($table =~ /^(talk|log)(2|text2)$/) {
	my $dblcheck = $dbo->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
	die "# Expecting: $dblcheck, but got $tct\n" unless $dblcheck == $tct;
    }

    my $verifykey = $ti->{verifykey};
    if ($opt_verify && $verifykey) {
        if ($table eq "dudata" || $table eq "ratelog") {
            print "# Verifying $table on size\n";
            my $pre = $dbo->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
            my $post = $dbch->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
            die "Moved sized is smaller" if $post < $pre;
        } else {
            print "# Verifying $table on key $verifykey\n";
            my %pre;
            my %post;
            my $sth;

            $sth = $dbo->prepare("SELECT $verifykey FROM $table WHERE $idxcol=$userid");
            $sth->execute;
            while (my @ar = $sth->fetchrow_array) {
                $_ = join(",",@ar);
                $pre{$_} = 1;
            }

            $sth = $dbch->prepare("SELECT $verifykey FROM $table WHERE $idxcol=$userid");
            $sth->execute;
            while (my @ar = $sth->fetchrow_array) {
                $_ = join(",",@ar);
                unless (delete $pre{$_}) {
                    die "Mystery row showed up in $table: uid=$userid, $verifykey=$_";
                }
            }
            my $count = scalar keys %pre;
            die "Rows not moved for uid=$userid, table=$table.  unmoved count = $count"
                if $count;
        }
    }

    $was_empty{$table} = 1 unless $tct;
    $rows += $tct;
}

print "# Rows done for '$user': $rows\n" if $optv;

# unset readonly and move to new cluster in one update
LJ::update_user($userid, { clusterid => $dclust, raw => "caps=caps&~(1<<$readonly_bit)" });
print "Moved.\n" if $optv;

# delete from source cluster
if ($opt_del) {
    print "Deleting from source cluster...\n" if $optv;
    foreach my $td (@to_delete) {
	my ($table, $pri) = @$td;
	while ($dbo->do("DELETE FROM $table WHERE $pri=$userid LIMIT 1000") > 0) {
	    print "  deleted from $table\n" if $optv;
	}
    }

    # s1stylecache table
    if (@styleids) {
	my $styleids_in = join(",", map { $dbo->quote($_) } @styleids);
	if ($dbo->do("DELETE FROM s1stylecache WHERE styleid IN ($styleids_in)") > 0) {
	    print "  deleted from s1stylecache\n" if $optv;
	}
    }
} else {
    # at minimum, we delete the clustertrack2 row so it doesn't get
    # included in a future ljumover.pl query from that cluster.
    $dbo->do("DELETE FROM clustertrack2 WHERE userid=$userid");
}

$dbh->do("UPDATE clustermove SET sdeleted=?, timedone=UNIX_TIMESTAMP() ".
	 "WHERE cmid=?", undef, $opt_del ? 1 : 0, $cmid);

exit 0;

sub fetch_tableinfo
{
    my @tables = (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL);
    my $memkey = "moveucluster:" . Digest::MD5::md5_hex(join(",",@tables));
    my $tinfo = LJ::MemCache::get($memkey) || {};
    foreach my $table (@tables) {
	next if $table eq "events" || $table eq "s1stylecache" ||
            $table eq "cmdbuffer" || $table eq "captcha_session";
	next if $tinfo->{$table};  # no need to load this one

	# find the index we'll use
	my $idx;     # the index name we'll be using
	my $idxcol;  # "userid" or "journalid"

	my $sth = $dbo->prepare("SHOW INDEX FROM $table");
	$sth->execute;
        my @pris;

	while (my $r = $sth->fetchrow_hashref) {
            push @pris, $r->{'Column_name'} if $r->{'Key_name'} eq "PRIMARY";
	    next unless $r->{'Seq_in_index'} == 1;
            next if $idx;
	    if ($r->{'Column_name'} eq "journalid" ||
		$r->{'Column_name'} eq "userid") {
		$idx = $r->{'Key_name'};
		$idxcol = $r->{'Column_name'};
	    }
	}

        shift @pris if @pris && ($pris[0] eq "journalid" || $pris[0] eq "userid");
        my $verifykey = join(",", @pris);

	die "can't find index for table $table\n" unless $idx;

	$tinfo->{$table}{idx} = $idx;
	$tinfo->{$table}{idxcol} = $idxcol;
        $tinfo->{$table}{verifykey} = $verifykey;

	my $cols = $tinfo->{$table}{cols} = [];
	my $colnum = 0;
	$sth = $dbch->prepare("DESCRIBE $table");
	$sth->execute;
	while (my $r = $sth->fetchrow_hashref) {
	    push @$cols, $r->{'Field'};
	    if ($r->{'Field'} eq $idxcol) {
		$tinfo->{$table}{pripos} = $colnum;
	    }
	    $colnum++;
	}
    }
    LJ::MemCache::set($memkey, $tinfo, 90);  # not for long, but quick enough to speed a series of moves
    return $tinfo;
}



