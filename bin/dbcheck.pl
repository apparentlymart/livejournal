#!/usr/bin/perl
#

use strict;
use DBI;
use Getopt::Long;

my $help = 0;
my $opt_fh = 0;
my $opt_fix = 0;
my $opt_ex = 0;
exit 1 unless GetOptions('help' => \$help,
			 'flushhosts' => \$opt_fh,
			 'fix' => \$opt_fix,
			 'exampleconf' => \$opt_ex,
			 );

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}

if ($help) {
    die ("Usage: dbcheck.pl [opts]\n" .
	 "    --help          Get this help\n" .
	 "    --flushhosts    Send 'FLUSH HOSTS' to each db as root.\n".
	 "    --fix           Fix (once) common problems.\n".
	 "    --exampleconf   Dump out prototype ~/var/dbcheck.conf file.\n"
	 );
}

if ($opt_ex) {
    print <DATA>;
    exit 0;
}

my $flush_host = sub {
    return unless $opt_fh;
    my $name = shift;
    my $dbh = shift;
    print "Flushing hosts on '$name' ... ";
    $dbh->do("FLUSH HOSTS");
    if ($dbh->err) {
	print "ERROR: " . $dbh->errstr . "\n";
    } else { 
	print "done.\n";
    }
};

my $conf_file = "$ENV{'LJHOME'}/var/dbcheck.conf";
unless (-e $conf_file) {
    die "No db_check.conf in ~/var/.  For help on syntax, run dbcheck.pl --exampleconf\n";
}
require $conf_file;

my $master = $LJ::DBCheck::master;
my $slaves = $LJ::DBCheck::slaves;

my $sth;
my @errors = ();

$| = 1;
print "Connecting to master... ";

my $mdb = DBI->connect("DBI:mysql:mysql:$master->{'ip'}",
		       $master->{'user'}, $master->{'pass'});
print "done.\n";

unless ($mdb) {
    print "error!\n";
    push @errors, "Can't connect to master db.";
    check_errors();
}

$flush_host->('master', $mdb);

$sth = $mdb->prepare("SHOW MASTER LOGS");
$sth->execute;
my @master_logs;
my $log_count = 0;
while (my ($log) = $sth->fetchrow_array) {
    push @master_logs, $log;
    $log_count++;
    print "Log: $log ($log_count)\n";
}
$sth->finish;

$sth = $mdb->prepare("SHOW MASTER STATUS");
$sth->execute;
my ($masterfile, $masterpos) = $sth->fetchrow_array;
$sth->finish;
printf "Master in $masterfile at $masterpos\n";

my $minlog = "";

foreach my $skey (keys %$slaves)
{
    my $s = $slaves->{$skey};
    printf "%-20s", $skey;

    if ($s->{'dead'}) {
	print "dead, skipping.\n";
	push @errors, "$skey is dead.";
	next;
    }

    my $dbh = DBI->connect("DBI:mysql:mysql:$s->{'ip'}",
			   $s->{'user'}, $s->{'pass'});
    unless ($dbh) {
	push @errors, "Can't connect to slave: $skey";
	next;
    }

    $flush_host->($skey, $dbh);

    my $sth;
    my $stalled = 0;
    my $ccount = 0;
    $sth = $dbh->prepare("SHOW PROCESSLIST");
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
    $sth = $dbh->prepare("SHOW SLAVE STATUS");
    $sth->execute;
    my $sl = $sth->fetchrow_hashref;
    $sth->finish;

    if ($opt_fix && $sl->{'Slave_Running'} eq "No" &&
	(
	 $sl->{'Last_error'} =~ /drop table livejournal\.tmp_selecttype_day/ ||
	 $sl->{'Last_error'} =~ /Duplicate entry.*hintlastnview/ ||
	 $sl->{'Last_error'} =~ /REPLACE INTO batchdelete/ ||
	 0
	 ))
    {
	$dbh->do("SET SQL_SLAVE_SKIP_COUNTER=1");
	$dbh->do("SLAVE START");	
	push @errors, "Slave restarted: $skey";
	$recheck = 1;
    }

    if ($opt_fix && $sl->{'Slave_Running'} eq "Yes" && $stalled)
    {
	my $new = $sl->{'Pos'} - 22;
	push @errors, "Moving back from $sl->{'Pos'} to $new";
	$dbh->do("CHANGE MASTER TO MASTER_LOG_POS=$new");
	$recheck = 1;
    }
    
    unless ($sl->{'Slave_Running'} eq "Yes") {
	push @errors, "Slave not running: $skey";
    }

    if ($recheck) {
	my $sth = $dbh->prepare("SHOW SLAVE STATUS");
	$sth->execute;
	$sl = $sth->fetchrow_hashref;
	$sth->finish;
    }

    $s->{'logfile'} = $sl->{'Log_File'};
    $s->{'pos'} = $sl->{'Pos'};

    unless ($s->{'logfile'}) {
	push @errors, "No log file for: $skey";
    }

    printf ("is in %s at %10d [%10d] c=%d\n", $s->{'logfile'}, 
	    $s->{'pos'}, $s->{'pos'} - $masterpos,
	    $ccount);
    $dbh->disconnect();

    if ($minlog eq "" || $s->{'logfile'} lt $minlog) { 
	$minlog = $s->{'logfile'};
    }
}

check_errors();

print "All slaves running.\n";
print "Minlog: $minlog\n";

if ($log_count >= 2 && $master_logs[0] lt $minlog)
{
    my $sql = "PURGE MASTER LOGS TO " . $mdb->quote($minlog);
    print $sql, "\n";
    $mdb->do($sql);
}
$mdb->disconnect;


sub check_errors
{
    if (@errors) {
	print STDERR "\nERRORS:\n";
	foreach (@errors) {
	    print STDERR "  * $_\n";
	}
	exit 1;
    }
}


# And now, the example conf file:
__DATA__
#!/usr/bin/perl
#

package LJ::DBCheck;

$master = { 
    'ip' => '10.0.0.2',
    'user' => 'root',
    'pass' => 'rootpassword', 
};

$slaves = {
    'orange' => { 'ip' => '10.0.0.5',
                   'user' => 'root',
                   'pass' => 'somepass', },
    'green' => { 'ip' => '10.0.0.7',
                  'user' => 'root',
                  'pass' => 'anotherpass', },
    # ...
};
