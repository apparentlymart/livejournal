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
my $opt_tablestatus;
my @opt_run;
exit 1 unless GetOptions('help' => \$help,
                         'flushhosts' => \$opt_fh,
                         'start' => \$opt_start,
                         'stop' => \$opt_stop,
                         'fix' => \$opt_fix,
                         'run=s' => \@opt_run,
                         'onlyerrors' => \$opt_err,
                         'all' => \$opt_all,
                         'tablestatus' => \$opt_tablestatus,
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
         "    --tablestatus   Show warnings about full/sparse tables.\n".
         "\n".
         "Commands\n".
         "   (none)           Shows replication status.\n".
         "   queries <host>   Shows active queries on host, sorted by running time.\n"
         );
}

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh("master");
die "Can't get master db handle\n" unless $dbh;

my %dbinfo;  # dbid -> hashref
my %name2id; # name -> dbid
my $sth;
my $masterid = 0;

my %subclust;  # id -> name of parent  (pork-85 -> "pork")

$sth = $dbh->prepare("SELECT dbid, name, masterid, rootfdsn FROM dbinfo");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    if ($_->{name} =~ /(.+)\-\d\d$/) {
	$subclust{$_->{dbid}} = $1;
	next;
    }
    next unless $_->{'dbid'};
    $dbinfo{$_->{'dbid'}} = $_;
    $name2id{$_->{'name'}} = $_->{'dbid'};
}

my %role;      # rolename -> dbid -> [ norm, curr ]
my %rolebyid;  # dbid -> rolename -> [ norm, curr ]
$sth = $dbh->prepare("SELECT dbid, role, norm, curr FROM dbweights");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    my $id = $_->{dbid};
    if ($subclust{$id}) {
	$id = $name2id{$subclust{$id}};
    }
    next unless defined $dbinfo{$id};
    $dbinfo{$id}->{'totalweight'} += $_->{'curr'};
    $role{$_->{role}}->{$id} = [ $_->{norm}, $_->{curr} ];
    $rolebyid{$id}->{$_->{role}} = [ $_->{norm}, $_->{curr} ];
}

my @errors;

my %checked;  # dbid -> 1
my $check = sub {
    my $dbid = shift;
    $checked{$dbid} = 1;
    my $d = $dbinfo{$dbid};
    die "Bogus DB: $dbid" unless $d;

    # calculate roles to show
    my $roles;
    {
	my %drole;  # display role -> 1
	foreach my $role (grep { $role{$_}{$dbid}[1] } keys %{$rolebyid{$dbid}}) {
	    my $drole = $role;
	    $drole =~ s/cluster(\d+)\d/cluster${1}0/;
	    $drole{$drole} = 1;
	}
	$roles = join(", ", sort keys %drole);
    }

    my $db = $LJ::DBIRole->get_dbh_conn($d->{'rootfdsn'});
    unless ($db) {
	printf("%4d %-15s %4s %12s  %14s  ($roles)\n",
	       $dbid,
	       $d->{name},
	       $d->{masterid} ? $d->{masterid} : "",
	       ) unless $opt_err;
	push @errors, "Can't connect to $d->{'name'}";
	return 0;
    }

    $sth = $db->prepare("SHOW PROCESSLIST");
    $sth->execute;
    my $pcount_total = 0;
    my $pcount_busy = 0;
    while (my $r = $sth->fetchrow_hashref) { 
	next if $r->{'State'} =~ /waiting for/i;
	next if $r->{'State'} eq "Reading master update";
	next if $r->{'State'} =~ /^(Has (sent|read) all)|(Sending binlog)/;
	$pcount_total++; 
	$pcount_busy++ if $r->{'State'};
    }

    $sth = $db->prepare("SHOW MASTER LOGS");
    $sth->execute;
    my @master_logs;
    my $log_count = 0;
    while (my ($log) = $sth->fetchrow_array) {
	push @master_logs, $log;
	$log_count++;
    }

    $sth = $db->prepare("SHOW MASTER STATUS");
    $sth->execute;
    my ($masterfile, $masterpos) = $sth->fetchrow_array;

    my $ss = $db->selectrow_hashref("show slave status");
    my $diff;
    if ($ss) {
	if ($ss->{'Slave_IO_Running'} eq "Yes" && $ss->{'Slave_SQL_Running'} eq "Yes") {
	    if ($ss->{'Master_Log_File'} eq $ss->{'Relay_Master_Log_File'}) {
		$diff = $ss->{'Read_Master_Log_Pos'} - $ss->{'Exec_master_log_pos'};
	    } else {
		$diff = "XXXXXXX";
		push @errors, "Wrong log file";
	    }
	} else {
	    $diff = "XXXXXXX";
	    push @errors, "Slave not running: $d->{name}";
	}
    } else {
	$diff = "-";  # not applicable
    }
    

    #print "$dbid of $d->{masterid}: $d->{name} ($roles)\n";
    printf("%4d %-15s %4s repl:%7s  conn:%4d/%4d  ($roles)\n",
	   $dbid, 
	   $d->{name},
	   $d->{masterid} ? $d->{masterid} : "",
	   $diff,
	   $pcount_busy, $pcount_total) unless $opt_err;
    

};

# do master
my $masterid = (keys %{$role{'master'}})[0];
$check->($masterid);

# then slaves
foreach my $id (sort { $dbinfo{$a}->{name} cmp $dbinfo{$b}->{name} }
		grep { ! $checked{$_} && $rolebyid{$_}->{slave} } keys %dbinfo) {
    $check->($id);
}

# now, figure out which remaining are associated with cluster roles (user clusters)
my %minclust;   # dbid -> minimum cluster number associated
my %is_master;  # dbid -> bool (is cluster master)
foreach my $dbid (grep { ! $checked{$_} } keys %dbinfo) {
    foreach my $role (keys %{ $rolebyid{$dbid} || {} }) {
	next unless $role =~ /^cluster(\d+)(.*)/;
	$minclust{$dbid} = $1 if ! $minclust{$dbid} || $1 < $minclust{$dbid};
	$is_master{$dbid} ||= $2 eq "" || $2 eq "a" || $2 eq "b";
    }
}

# then misc
foreach my $id (sort { $dbinfo{$a}->{name} cmp $dbinfo{$b}->{name} }
                grep { ! $checked{$_} && ! $minclust{$_} } keys %dbinfo) {
    $check->($id);
}


# then clusters, in order
foreach my $id (sort { $minclust{$a} <=> $minclust{$b} ||
			   $is_master{$b} <=> $is_master{$a} }
                grep { ! $checked{$_} && $minclust{$_} } keys %dbinfo) {
    $check->($id);
}


if (@errors) {
    if ($opt_err) {
	my %ignore;
	open(EX, "$ENV{'HOME'}/.dbcheck.ignore");
	while (<EX>) {
	    s/\s+$//;
	    $ignore{$_} = 1;
	}
	close EX;
	@errors = grep { ! $ignore{$_} } @errors;
    }
    print STDERR "\nERRORS:\n" if @errors;
    foreach (@errors) {
	print STDERR "  * $_\n";
    }
}

