#!/usr/bin/perl
#

use strict;
use DBI;
use Getopt::Long;

my $help = 0;
my $opt_fh = 0;
my $opt_fix = 0;
my $opt_start = 0;
my $opt_stop = 0;
my $opt_err = 0;
my $opt_all = 0;
my @opt_run;
exit 1 unless GetOptions('help' => \$help,
                         'flushhosts' => \$opt_fh,
                         'start' => \$opt_start,
                         'stop' => \$opt_stop,
                         'fix' => \$opt_fix,
                         'run=s' => \@opt_run,
                         'onlyerrors' => \$opt_err,
                         'all' => \$opt_all,
                         );

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}

if ($help) {
    die ("Usage: dbcheck.pl [opts] [[cmd] args...]\n" .
         "    --all           Check all hosts, even those with no weight assigned.\n" .
         "    --help          Get this help\n" .
         "    --flushhosts    Send 'FLUSH HOSTS' to each db as root.\n".
         "    --fix           Fix (once) common problems.\n".
         "    --stop          Stop replication.\n".
         "    --start         Start replication.\n".
         "    --run <sql>     Run arbitrary SQL.\n".
         "    --onlyerrors    Will be silent unless there are errors.\n".
         "\n".
         "Commands\n".
         "   (none)           Shows replication status.\n".
         "   queries <host>   Shows active queries on host, sorted by running time.\n"
         );
}

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

unless ($LJ::DBWEIGHTS_FROM_DB) {
    #die "This tool only works when using \$DBWEIGHTS_FROM_DB (db weights ".
#	"& info stored in database, not in ljconfig)\n";
}

my $dbh = LJ::get_dbh("master");
die "Can't get master db handle\n" unless $dbh;

my %dbinfo;  # dbid -> hashref
my %slaves;  # dbid -> arrayref<dbid>
my %name2id; # name -> dbid
my $sth;
my $masterid = 0;
$sth = $dbh->prepare("SELECT dbid, name, masterid, rootfdsn FROM dbinfo");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    next unless $_->{'dbid'};
    $dbinfo{$_->{'dbid'}} = $_;
    $name2id{$_->{'name'}} = $_->{'dbid'};
    push @{$slaves{$_->{'masterid'}}}, $_->{'dbid'};
    if ($_->{'masterid'} == 0) { 
	if ($masterid) { die "Config problem: two master dbs?\n"; }
	$masterid = $_->{'dbid'}; 
    }
}

$sth = $dbh->prepare("SELECT dbid, role, norm, curr FROM dbweights");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    next unless defined $dbinfo{$_->{'dbid'}};
    $dbinfo{$_->{'dbid'}}->{'totalweight'} += $_->{'curr'};
}

die "No master found?" unless $masterid;

my $sth;
my $cmd = shift @ARGV;

if ($cmd eq "queries") {
    my $host = shift @ARGV;
    my $s = $dbinfo{$name2id{$host}};
    unless ($s) { die "Unknown slave: $host\n"; }

    my $dbh = $LJ::DBIRole->get_dbh_conn($s->{'rootfdsn'});
    die "Can't connect to slave: $host\n" unless $dbh;

    my $ts = $dbh->selectall_hashref("SHOW FULL PROCESSLIST");
    foreach my $t (sort { $a->{'Time'} <=> $b->{'Time'} } @$ts) {
        next if ($t->{'Command'} eq "Sleep" ||
                 $t->{'Command'} eq "Connect");
        my $cmd = $t->{'Info'};
        $cmd =~ s/\n/ /g;
        print "$t->{'Time'}\t($t->{'Id'})\t$cmd\n" unless $opt_err;
    }
    exit;
} elsif ($cmd) {
    die "Unknown command: $cmd\n";
}

my $pr = sub {
    return if $opt_err;
    print $_[0];
};

my $flush_host = sub {
    return unless $opt_fh;
    my $id = shift;
    my $dbh = shift;
    my $name = $dbinfo{$id}->{'name'};
    print "Flushing hosts on '$name' ... ";
    $dbh->do("FLUSH HOSTS");
    if ($dbh->err) {
        print "ERROR: " . $dbh->errstr . "\n";
    } else { 
        print "done.\n";
    }
};

# check a master and all its slaves' positions
my $check = sub 
{
    my @errors;

    my $id = shift;
    my $chkref = shift;

    my $d = $dbinfo{$id};
    return if $d->{name} =~ /\-\d+$/;

    $pr->("$d->{'name'}:\n");
    my $db = $LJ::DBIRole->get_dbh_conn($d->{'rootfdsn'});
    unless ($db) {
	push @errors, "Can't connect to $d->{'name'}";
	return 0;
    }

    my $mcount = 0;
    $sth = $db->prepare("SHOW PROCESSLIST");
    $sth->execute;
    while ($sth->fetchrow_hashref) { $mcount++; }
    print "  Conn: $mcount\n" unless $opt_err;

    $sth = $db->prepare("SHOW MASTER LOGS");
    $sth->execute;
    my @master_logs;
    my $log_count = 0;
    while (my ($log) = $sth->fetchrow_array) {
	push @master_logs, $log;
	$log_count++;
	$pr->("  Log: $log ($log_count)\n");
    }

    $sth = $db->prepare("SHOW MASTER STATUS");
    $sth->execute;
    my ($masterfile, $masterpos) = $sth->fetchrow_array;
    $sth->finish;
    $pr->("  Master in $masterfile at $masterpos\n");

    my $minlog = "";

    $pr->("  Slaves:\n");
    $| = 1;
    foreach my $sid (@{$slaves{$id}})
    {
	my $s = $dbinfo{$sid};
	my $skey = $s->{'name'};
	next if $s->{'name'} =~ /\-\d+$/;

	if (defined $slaves{$sid}) {
	    push @$chkref, $sid;
	}

	$pr->(sprintf("    %-20s", $skey));

	unless ($s->{'totalweight'} || $opt_all) {
	    $pr->("dead, skipping.\n");
	    push @errors, "$s->{'name'} is dead.";
	    next;
	}

	my $dbsl = $LJ::DBIRole->get_dbh_conn($s->{'rootfdsn'});
	unless ($dbsl) {
            $pr->("\n");
            push @errors, "Can't connect to slave: $s->{'name'}";
            next;
	}

	$flush_host->($sid, $dbh);

	if ($opt_start) { $dbsl->do("SLAVE START"); }
	if ($opt_stop) { $dbsl->do("SLAVE STOP"); }
	foreach (@opt_run) { 
	    print "Running: $_\n";
	    $dbsl->do($_); 
	    print $dbh->err ? $dbh->errstr : "OK";
	    print "\n";
	}
	
	my $ver = $dbsl->selectrow_array("SELECT VERSION()");
	
	my $sth;
	my $stalled = 0;
	my $ccount = 0;
	$sth = $dbsl->prepare("SHOW PROCESSLIST");
	$sth->execute;
	while (my $c = $sth->fetchrow_hashref) {
	    $ccount++;
	    next unless ($c->{'User'} eq "system user");
	    if ($c->{'State'} =~ /after a failed read/) {
		push @errors, "Neg22: $skey";
		$stalled = 1;
	    }
	}

	my $recheck = 0;
	$sth = $dbsl->prepare("SHOW SLAVE STATUS");
	$sth->execute;
	my $sl = $sth->fetchrow_hashref;

	# MySQL 4.0 support
	unless (defined $sl->{'Slave_Running'}) {
	    $sl->{'Slave_Running'} = $sl->{'Slave_SQL_Running'};
	    $sl->{'Log_File'} = $sl->{'Relay_Master_Log_File'} || $sl->{'Master_Log_File'};
	    $sl->{'Pos'} = $sl->{'Exec_master_log_pos'};
	}

	if ($opt_fix && $sl->{'Slave_Running'} eq "No" &&
	    $sl->{'Last_error'} =~ /Duplicate entry '(\d+)-(\d+)' for key 1' on query 'INSERT INTO log2/)
	{
	    my ($uid, $itid) = ($1, $2);
	    $dbsl->do("DELETE FROM log2 WHERE journalid=? AND jitemid=?", undef, $uid, $itid);
	    $dbsl->do("SET SQL_SLAVE_SKIP_COUNTER=1");
	    $dbsl->do("SLAVE START");
	    push @errors, "Slave restarted by deleting log2 row ($uid-$itid): $skey";
	    $recheck = 1;
	}

	if ($opt_fix && $sl->{'Slave_Running'} eq "No" &&
	    $sl->{'Last_error'} =~ /Duplicate entry '(\d+)-(\d+)' for key 1' on query '(INSERT|REPLACE) INTO talk2/)
	{
	    my ($uid, $itid) = ($1, $2);
	    open (LG, ">>$ENV{'LJHOME'}/var/talk2-errors.log") or die;
	    print LG "$skey: $uid-$itid\n";
	    close LG;
	    $dbsl->do("DELETE FROM talk2 WHERE journalid=? AND jtalkid=?", undef, $uid, $itid);
	    $dbsl->do("SLAVE START");
	    push @errors, "Slave restarted by deleting talk2 row ($uid-$itid): $skey";
	    $recheck = 1;
	}

	if ($opt_fix && $sl->{'Slave_Running'} eq "No" &&
	    $sl->{'Last_error'} =~ /Duplicate entry '(\d+)-(\d+)' for key 1' on query 'INSERT INTO sessions/)
	{
	    my ($uid, $sessid) = ($1, $2);
	    $dbsl->do("DELETE FROM sessions WHERE userid=? AND sessid=?", undef, $uid, $sessid);
	    $dbsl->do("SET SQL_SLAVE_SKIP_COUNTER=1");
	    $dbsl->do("SLAVE START");
	    push @errors, "Slave restarted by deleting session row ($uid-$sessid): $skey";
	    $recheck = 1;
	}

	if ($opt_fix && $sl->{'Slave_Running'} eq "No" &&
	    (
	     $sl->{'Last_error'} =~ /drop table livejournal\.tmp_selecttype_day/ ||
	     $sl->{'Last_error'} =~ /Duplicate entry.*hintlastnview/ ||
	     $sl->{'Last_error'} =~ /REPLACE INTO batchdelete/ ||
	     0
	     ))
	{
	    $dbsl->do("SET SQL_SLAVE_SKIP_COUNTER=1");
	    $dbsl->do("SLAVE START");	
	    push @errors, "Slave restarted: $skey";
	    $recheck = 1;
	}

	if ($opt_fix && $sl->{'Slave_Running'} eq "Yes" && $stalled)
	{
	    my $new = $sl->{'Pos'} - 22;
	    #push @errors, "Moving back from $sl->{'Pos'} to $new";
	    #$dbsl->do("CHANGE MASTER TO MASTER_LOG_POS=$new");
	    #$recheck = 1;
	}
    
	unless ($sl->{'Slave_Running'} eq "Yes") {
	    push @errors, "Slave not running: $skey";
	}

	if ($recheck) {
	    my $sth = $dbsl->prepare("SHOW SLAVE STATUS");
	    $sth->execute;
	    $sl = $sth->fetchrow_hashref;
	    $sth->finish;
	}

	$s->{'logfile'} = $sl->{'Log_File'};
	$s->{'pos'} = $sl->{'Pos'};

	unless ($s->{'logfile'}) {
	    push @errors, "No log file for: $skey";
	}

	$pr->(sprintf ("is in %s at %10d [%10d] c=%d v=$ver\n", $s->{'logfile'}, 
		       $s->{'pos'}, $s->{'pos'} - $masterpos,
		       $ccount));

	if ($minlog eq "" || $s->{'logfile'} lt $minlog) { 
	    $minlog = $s->{'logfile'};
	}
    }

    if (@errors) {
        print STDERR "\nERRORS:\n";
        foreach (@errors) {
            print STDERR "  * $_\n";
        }
	return 0;
    }

    if ($log_count >= 2 && $master_logs[0] lt $minlog)
    {
	my $sql = "PURGE MASTER LOGS TO " . $db->quote($minlog);
	$pr->("$sql\n");
	$db->do($sql);
    }
    
    return 1;
};

my @to_check = ($masterid);
$flush_host->($masterid, $dbh);
my $good = 1;
while (@to_check) {
    $good = 0 unless $check->(shift @to_check, \@to_check);
}

exit 1 unless $good;
$pr->("Alles gut.\n");


