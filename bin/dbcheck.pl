#!/usr/bin/perl
#

use strict;
use DBI;
use Getopt::Long;

my $help = 0;
my $opt_fh = 0;
my $opt_fix = 0;
my $opt_ex = 0;
my $opt_start = 0;
my $opt_stop = 0;
my $opt_err = 0;
my @opt_run;
exit 1 unless GetOptions('help' => \$help,
                         'flushhosts' => \$opt_fh,
                         'start' => \$opt_start,
                         'stop' => \$opt_stop,
                         'fix' => \$opt_fix,
                         'run=s' => \@opt_run,
                         'exampleconf' => \$opt_ex,
                         'onlyerrors' => \$opt_err,
                         );

unless (-d $ENV{'LJHOME'}) { 
    die "\$LJHOME not set.\n";
}

if ($help) {
    die ("Usage: dbcheck.pl [opts] [[cmd] args...]\n" .
         "    --help          Get this help\n" .
         "    --flushhosts    Send 'FLUSH HOSTS' to each db as root.\n".
         "    --fix           Fix (once) common problems.\n".
         "    --exampleconf   Dump out prototype ~/var/dbcheck.conf file.\n".
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

my $cmd = shift @ARGV;

if ($cmd eq "queries") {
    my $host = shift @ARGV;
    my $s = $slaves->{$host};
    unless ($s) { die "Unknown slave: $host\n"; }

    my $dbh = DBI->connect("DBI:mysql:mysql:$s->{'ip'}",
                           $s->{'user'}, $s->{'pass'});
    die "Can't connect to slave: $host\n" unless ($dbh);

    my $ts = $dbh->selectall_hashref("SHOW FULL PROCESSLIST");
    foreach my $t (sort { $a->{'Time'} <=> $b->{'Time'} } @$ts) {
        next if ($t->{'Command'} eq "Sleep" ||
                 $t->{'Command'} eq "Connect");
        my $cmd = $t->{'Info'};
        $cmd =~ s/\n/ /g;
        print "$t->{'Time'}\t($t->{'Id'})\t$cmd\n";
    }
    exit;
} elsif ($cmd) {
    die "Unknown command: $cmd\n";
}


my @errors = ();

$| = 1;
print "Connecting to master... " unless $opt_err;

my $mdb = DBI->connect("DBI:mysql:mysql:$master->{'ip'}",
                       $master->{'user'}, $master->{'pass'});
print "done.\n" unless $opt_err;

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
    print "Log: $log ($log_count)\n" unless $opt_err;
}
$sth->finish;

$sth = $mdb->prepare("SHOW MASTER STATUS");
$sth->execute;
my ($masterfile, $masterpos) = $sth->fetchrow_array;
$sth->finish;
printf "Master in $masterfile at $masterpos\n" unless $opt_err;

my $minlog = "";

foreach my $skey (keys %$slaves)
{
    my $s = $slaves->{$skey};
    printf "%-20s", $skey unless $opt_err;

    if ($s->{'dead'}) {
        print "dead, skipping.\n" unless $opt_err;
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

    if ($opt_start) { $dbh->do("SLAVE START"); }
    if ($opt_stop) { $dbh->do("SLAVE STOP"); }
    foreach (@opt_run) { 
        print "Running: $_\n";
        $dbh->do($_); 
        print $dbh->err ? $dbh->errstr : "OK";
        print "\n";
    }

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
            $ccount) unless $opt_err;
    $dbh->disconnect();

    if ($minlog eq "" || $s->{'logfile'} lt $minlog) { 
        $minlog = $s->{'logfile'};
    }
}

check_errors();

unless ($opt_err) {
    print "All slaves running.\n";
    print "Minlog: $minlog\n";
}

if ($log_count >= 2 && $master_logs[0] lt $minlog)
{
    my $sql = "PURGE MASTER LOGS TO " . $mdb->quote($minlog);
    print $sql, "\n" unless ($opt_err);
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
