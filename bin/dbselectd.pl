#!/usr/bin/perl -w
#
# DB selector daemon. Returns connect information on a preferred DB
# to a requestor.
#
# <LJDEP>
# lib: Getopt::Long, POSIX::, IO::Socket, IO::Select, Socket::, Fcntl::, DBI::
# lib: cgi-bin/ljconfig.pl
# </LJDEP>

use Getopt::Long;
use POSIX;
use IO::Socket;
use IO::Select;
use strict;
use Socket;
use Fcntl;
use DBI;

my $PORT = 5151;
my $PIDFILE = "$ENV{'LJHOME'}/var/dbselectd.pid";

my $SELECT_DELAY = 0.3;

# temporary:
my $DBINFO_FILE = "$ENV{'LJHOME'}/cgi-bin/ljconfig.pl";
my $opt_foreground = 0;
GetOptions("foreground" => \$opt_foreground);

my $pid;

# statistics on known databases
my %db_lastcheck;
my %db_conncount;
my $conf_modtime = 0;
my $conf_stattime = 0;

# Buffers.
my %inbuffer = ();
my %outbuffer = ();
my %cmd = ();
my %clientinfo = ();

sub connect_to
{
    my $svr = shift;
    my $dbh;
    
    if (ref $LJ::DBCACHE{$svr}) 
    {
        $dbh = $LJ::DBCACHE{$svr};

	# make sure connection is still good.
	my $sth = $dbh->prepare("SELECT CONNECTION_ID()");  # mysql specific
	$sth->execute;
	my ($id) = $sth->fetchrow_array;
	if ($id) { return $dbh; }
	undef $dbh;
	undef $LJ::DBCACHE{$svr};
    }

    my $dbname = $LJ::DBINFO{$svr}->{'dbname'} || "livejournal";
    $dbh = DBI->connect("DBI:mysql:$dbname:$LJ::DBINFO{$svr}->{'host'}", 
			$LJ::DBINFO{$svr}->{'user'},
			$LJ::DBINFO{$svr}->{'pass'},
			{
			    PrintError => 0,
			});
    if ($dbh) 
    {
	$LJ::DBCACHE{$svr} = $dbh;
	return $dbh;
    }

    return undef;
}

sub db_can
{
    my $svr = shift;
    my $cap = shift;
    return $LJ::DBINFO{$svr}->{'role'}->{$cap};
}

sub check_server
{
    my $svr = shift;
    delete $db_conncount{$svr};
    delete $db_lastcheck{$svr};

    my $dbh = connect_to($svr);
    return unless (defined $dbh);

    my $sth = $dbh->prepare("SHOW PROCESSLIST");
    $sth->execute;
    my $ct = 0;
    while (my $r = $sth->fetchrow_hashref)
    {
	# weight busy connections more than idle ones.
	if ($r->{'State'}) { $ct += 2; }
	else { $ct += 1; }
    }
    $db_conncount{$svr} = $ct;
    $db_lastcheck{$svr} = time();
}

sub connection_load
{
    my $svr = shift;
    my $time = time();
    if (! defined $db_lastcheck{$svr} || 
	$time - $db_lastcheck{$svr} > 10) 
    {
	check_server($svr);
    }
    return $db_conncount{$svr};
}

sub server_power
{
    my $svr = shift;
    my $cap = shift;

    my $weight = $LJ::DBINFO{$svr}->{'role'}->{$cap} || 1;
    my $connections = connection_load($svr);
    if (defined $connections) {
	$connections ||= 1;
    } else {
	return 0;
    }
    return ($weight / $connections);
}

sub use_what
{
    my $c = shift;
    my $cap = shift;

    ## reload the DB info file if it's been more than 5 seconds since 
    ## its last stat time and if it's changed since what we remember.
    my $time = time();
    if ($conf_stattime + 5 < $time)
    {
	my $modtime = (stat($DBINFO_FILE))[9];
	if ($modtime > $conf_modtime) {
	    delete $INC{$DBINFO_FILE};
	    require $DBINFO_FILE;
	    $conf_modtime = $modtime;
	    $conf_stattime = $time;
	}
    }
    
    my %cand = ();  # candidates

    # best candidate is one the client is already connected to
    foreach my $svr (keys %{$c->{'has'}}) {
	if (db_can($svr, $cap)) {
	    $cand{$svr} = 1;   
	}
    }
   
    # if not connected to anything suitable, then:
    unless (%cand)
    {
	# every db with that capability is a good candidate
	foreach my $svr (keys %LJ::DBINFO) {
	    if (db_can($svr, $cap)) { 
		$cand{$svr} = 1;
	    }
	}
    }

    my @cands = keys %cand;
    
    # sort valid candidates by server's connections
    @cands = sort { server_power($b, $cap) <=> server_power($a, $cap) } @cands;

    # use the one with the highest score:
    my $use = $cands[0];
    if ($use) {
	unless (defined $LJ::DBINFO{$use}->{'dbname'}) {
	    $LJ::DBINFO{$use}->{'dbname'} = "livejournal";
	}
	return join(" ", $use, map { $LJ::DBINFO{$use}->{$_} } qw(host user pass dbname));
    } else {
	return "--";
    }
}

sub handle 
{
    my $select = shift;
    my $client = shift;
    my $line = shift;
    my $c = ($clientinfo{$client} ||= {});
    my $out = \$outbuffer{$client};
    
    $line =~ s/^(\S*)\s*//;
    my $cmd = $1;

    if ($cmd eq "HAVE") {
	foreach (split(/,/, $line)) {
	    next if ($_ eq "master");
	    $c->{'has'}->{$_} = 1;
	}
	$$out = "OK\n";
	return;
    }

    if ($cmd eq "NEED") {
	my $cap = $line;
	my $use = use_what($c, $cap);
	$$out = "USE $use\n";
	return;
    }

    $$out = "unknown command.\n";
}

# Server crap is below.

$SIG{'TERM'} = sub {
    unlink($PIDFILE);
    exit 1;
};

if (-e $PIDFILE) {
  print "$PIDFILE exists, quitting.\n";
  exit 1;
}

sub write_pid
{
    my $p = shift;
    open(PID, ">$PIDFILE")   or die "Couldn't open $PIDFILE for writing: $!\n";
    print PID $p;
    close(PID);
}

if ($opt_foreground) {
    print "Running in foreground...\n";
    $pid = $$;
    write_pid($pid);
    $SIG{'INT'} = sub {
        unlink($PIDFILE);
        exit 1;
    };
} else {
    print "Forking off and initializing...\n";
    if ($pid = fork) {
	# Parent, log pid and exit.
	write_pid($pid);
	print "Closing ($pid) wrote to $PIDFILE\n";
	exit;
    }
}

sub killpid_die
{
    my $msg = shift;
    unlink $PIDFILE;
    die $msg;
}

# Connection stuff.
my $server = IO::Socket::INET->new(
				   "LocalPort" => $PORT, 
				   "Listen" => 10,
				   "ReuseAddr" => 1,
				   "Reuse" => 1,
				   ) or killpid_die "Can't make server socket: $@\n";

nonblock($server);
$server->sockopt(SO_REUSEADDR, 1);
my $select = IO::Select->new($server);

print "Looping.\n";

while(1) 
{
  my $client;
  my $rv;
  my $data;

  # Got connection? Got data?
  foreach $client ($select->can_read($SELECT_DELAY)) {
    if ($client == $server) {
        # New connection, since there's stuff to read from the server sock.
        $client = $server->accept();
        $select->add($client);
        # If the nonblocking mess fails, uh, give up.
        unless (nonblock($client)) {
            $select->remove($client);
        }
    } else {
        # Read what data we have.
        $data = '';
        $rv = $client->recv($data, POSIX::BUFSIZ, 0);

        unless (defined($rv) && length($data)) {
            # If a socket says you can read, but there's nothing there, it's
            # actually dead. Clean it up.
	    cleanup($client);

            $select->remove($client);
            close($client);
            next;
        }

        $inbuffer{$client} .= $data;
        # Check to see if there's a newline at the end. If it is, the
        # command is finished. There's only one command line, so I won't
        # bother making %cmd a hash with array references to request
        # lines. Although this might be needed in the future.
        if ($inbuffer{$client} =~ s/^.*\n//) {
            $cmd{$client} = $&;
            delete $inbuffer{$client};
        }
    }

  }

  # Deal with cmd stuff.
  foreach $client (keys %cmd) {
      my $cmd = $cmd{$client};
      $cmd =~ s/[\n\r]+$//;
      handle($select, $client, $cmd);
  }
  %cmd = ();

  # Flush buffers
  foreach $client ($select->can_write($SELECT_DELAY)) {
      # Don't try if there's nothing there.
      next unless exists $outbuffer{$client};

      $rv = $client->send($outbuffer{$client}, 0);
      unless (defined $rv) {
          # Something weird happened if we get here, I'll bitch if we ever
          # need logging on this thing.
          next;
      }
      if ($rv == length $outbuffer{$client} || $! == POSIX::EWOULDBLOCK) {
          substr($outbuffer{$client}, 0, $rv) = '';
          delete $outbuffer{$client} unless length $outbuffer{$client};
      } else {
          # Ahh, something broke. If it was going to block, the above would
          # catch it. Close up...
	  cleanup($client);

          $select->remove($client);
          close($client);
          next;
      }

  }

}

# Does the messy Socket based nonblock routine...
sub nonblock {
    my $socket = shift;
    my $flags;

    $flags = fcntl($socket, F_GETFL, 0) or return 0;
    fcntl($socket, F_SETFL, $flags | O_NONBLOCK) or return 0;

    return 1;
}

sub cleanup
{
    my $client = shift;

    delete $inbuffer{$client};
    delete $outbuffer{$client};
    delete $cmd{$client};
    delete $clientinfo{$client};
}
