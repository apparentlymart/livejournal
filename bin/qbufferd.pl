#!/usr/bin/perl
#
# <LJDEP>
# lib: Proc::ProcessTable, cgi-bin/ljlib.pl
# </LJDEP>

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
exit unless ($LJ::BUFFER_QUERIES);

use Proc::ProcessTable;

$DELAY = $LJ::QBUFFERD_DELAY || 15;

$pidfile = '/home/lj/var/qbufferd.pid';
if (-e $pidfile) {
    open (PID, $pidfile);
    my $pid;
    chomp ($pid = <PID>);
    close PID;
    my $processes = Proc::ProcessTable->new()->table;
    if (grep { $_->cmndline =~ /qbufferd/ } @$processes) {
	exit;
    }
}

$is_parent = 0;
$running = 0;

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
while (1)
{
    my $dbh = LJ::get_dbh("master");

    $sth = $dbh->prepare("SELECT tablename, count(*) FROM querybuffer GROUP BY 1");
    $sth->execute;
    my @tables;
    while (my ($table, $count) = $sth->fetchrow_array) {
	next if ($table =~ /^do:/);
	push @tables, $table;
    }
    $sth->finish;
    
    foreach my $table (@tables) {
	my $count = LJ::query_buffer_flush($dbh, $table);
    }
    sleep $DELAY;
};
