#!/usr/bin/perl
#
# <LJDEP>
# lib: Proc::ProcessTable, cgi-bin/ljlib.pl
# </LJDEP>

use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

use Proc::ProcessTable;

my $DELAY = $LJ::QBUFFERD_DELAY || 15;

my $pidfile = '/home/lj/var/qbufferd.pid';
my $pid;
if (-e $pidfile) {
    open (PID, $pidfile);
    chomp ($pid = <PID>);
    close PID;
    my $processes = Proc::ProcessTable->new()->table;
    if (grep { $_->cmndline =~ /qbufferd/ } @$processes) {
	exit;
    }
}

my $is_parent = 0;
my $running = 0;

END {
    unless ($is_parent || ! $running) {
	print "END-STOP\n";
	&stop_qbufferd();
    }
}

$SIG{'INT'} = \&stop_qbufferd;
$SIG{'TERM'} = \&stop_qbufferd;
$SIG{'HUP'} = sub { 
    # nothing.  maybe later make a HUP force a flush?
};

# Perhaps I should give it a command to not do this in the future.
if ($pid = fork) 
{
    $is_parent = 1;
    open (PID, ">$pidfile") or die "Couldn't write PID file.  Exiting.\n";
    print PID $pid, "\n";
    close PID;
    print "qbufferd started with pid $pid\n";
    if (-s $pidfile) { print "pid file written ($pidfile)\n"; }
    exit;
} 

sub stop_qbufferd
{
    print "Quitting.\n";
    unlink $pidfile;
    exit;
}

$running = 1;
while (LJ::start_request())
{
    my $cycle_start = time();

    # do main cluster updates
    my $dbh = LJ::get_dbh("master");
    if ($dbh) {
	my $sth = $dbh->prepare("SELECT tablename, COUNT(*) FROM querybuffer GROUP BY 1");
	$sth->execute;
	my @tables;
	while (my ($table, $count) = $sth->fetchrow_array) {
	    push @tables, $table;
	}
	foreach my $table (@tables) {
	    my $count = LJ::query_buffer_flush($dbh, $table);
	}
    }
	
    # handle clusters
    foreach my $c (@LJ::CLUSTERS) {
	my $db = LJ::get_cluster_master($c);
	next unless $db;

	my $sth = $db->prepare("SELECT cmd, COUNT(*) FROM cmdbuffer GROUP BY 1");
	$sth->execute;
	my @cmds;
	while (my ($cmd, $count) = $sth->fetchrow_array) {
	    LJ::cmd_buffer_flush($dbh, $db, $cmd);
	}
    }

    my $elapsed = time() - $cycle_start;
    sleep ($DELAY-$elapsed) if $elapsed < $DELAY;
};
