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

# temporary:
%LJ::DBINFO = (
	       'master' => {
		   'host' => '10.0.0.2',
		   'user' => 'lj',
		   'pass' => 'ljpass',  
		   'role' => { 
		       'txt' => 0.2,
		       'hints' => 1,
		   },
	       },
	       'kenny' => {
		   'host' => '10.0.0.1',
		   'user' => 'ljro',
		   'pass' => 'ljropass',
		   'role' => { 
		       'txt' => 0.4,
		       'hints' => 3,
		       'slave' => 1,
		   },
	       },
	       'marklar' => {
		   'host' => '10.0.0.15',
		   'user' => 'ljro',
		   'pass' => 'ljropass',
		   'role' => { 
		       'txt' => 0.4,
		       'hints' => 2,
		       'slave' => 1,
		   },
	       },
	       );

my $opt_foreground = 0;
GetOptions("foreground" => \$opt_foreground);

my $pid;

# Buffers.
my %inbuffer = ();
my %outbuffer = ();
my %ready = ();


sub handle 
{
    my $client = shift;
    my $request = $ready{$client};

    # Do the magic handling stuff!
    # Nice candy shell around the whole thing :)
    # Put the results into %outbuffer, like so.
    $outbuffer{$client} = "Test data!\n";

    # Remove the request.
    delete $ready{$client};
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
} else {
    print "Forking off and initializing...\n";
    if ($pid = fork) {
	# Parent, log pid and exit.
	write_pid($pid);
	print "Closing ($pid) wrote to $PIDFILE\n";
	exit;
    }
}

# Connection stuff.
my $server = IO::Socket::INET->new(LocalPort => $PORT, Listen => 10) or die "Can't make server socket: $@\n";

nonblock($server);
my $select = IO::Select->new($server);

print "Looping.\n";

# Main loop-de-loop.
while(1) {
  my $client;
  my $rv;
  my $data;

  # Got connection? Got data?
  foreach $client ($select->can_read(1)) {
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
            delete $inbuffer{$client};
            delete $outbuffer{$client};
            delete $ready{$client};

            $select->remove($client);
            close($client);
            next;
        }

        $inbuffer{$client} .= $data;
        # Check to see if there's a newline at the end. If it is, the
        # command is finished. There's only one command line, so I won't
        # bother making %ready a hash with array references to request
        # lines. Although this might be needed in the future.
        if ($inbuffer{$client} =~ /\n$/) {
            $ready{$client} = chomp($inbuffer{$client});
            delete $inbuffer{$client};
        }
    }

  }

  # Deal with ready stuff.
  foreach $client (keys %ready) {
      handle($client);
  }

  # Flush de boofers.
  foreach $client ($select->can_write(1)) {
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
          delete $inbuffer{$client};
          delete $outbuffer{$client};
          delete $ready{$client};

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
