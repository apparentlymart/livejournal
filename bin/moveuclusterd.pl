#!/usr/bin/perl
##############################################################################

=head1 NAME

moveuclusterd - User-mover task coordinater daemon

=head1 SYNOPSIS

  $ moveuclusterd OPTIONS

=head2 OPTIONS

=over 4

=item -d, --debug

Output debugging information in addition to normal progress messages. May be
specified more than once to increase debug level.

=item -D, --daemon

Background the program.

=item -h, --help

Output a help message and exit.

=item -H, --host=HOST

Listen on the specified I<HOST> instead of the default '0.0.0.0'.

=item -p, --port=PORT

Listen to the given I<PORT> instead of the default 2789.

=item -r, --defaultrate=INTEGER

Set the default rate limit for any source cluster which has not had its rate set
to I<INTEGER>. The default rate is 1.

=back

=head1 REQUIRES

I<Token requires line>

=head1 DESCRIPTION

None yet.

=head1 AUTHOR

Michael Granger E<lt>ged@danga.comE<gt>

Copyright (c) 2004 Danga Interactive. All rights reserved.

This module is free software. You may use, modify, and/or redistribute this
software under the terms of the Perl Artistic License. (See
http://language.perl.com/misc/Artistic.html)

=cut

##############################################################################
package moveuclusterd;
use strict;
use warnings qw{all};


###############################################################################
###  I N I T I A L I Z A T I O N
###############################################################################
BEGIN {

	# Turn STDOUT buffering off
	$| = 1;

	# Versioning stuff and custom includes
	use vars qw{$VERSION $RCSID};
	$VERSION	= do { my @r = (q$Revision$ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
	$RCSID		= q$Id$;

	# Define some constants
	use constant TRUE	=> 1;
	use constant FALSE	=> 0;

    use lib "$ENV{LJHOME}/cgi-bin";
    require "ljlib.pl";

	# Modules
    use Carp                qw{croak confess};
	use Getopt::Long		qw{GetOptions};
	use Pod::Usage			qw{pod2usage};

    Getopt::Long::Configure( 'bundling' );
}


###############################################################################
###	C O N F I G U R A T I O N   G L O B A L S
###############################################################################

### Main body
MAIN: {
	my (
		$debugLevel,			# Debugging level to set in server
		$helpFlag,				# User requested help?
		$daemonFlag,            # Background after starting?
        $defaultRate,           # Default src cluster rate cmdline setting
		$server,                # JobServer object
		%config,                # JobServer configuration
		$port,                  # Port to listen on
		$host,                  # Address to listen on
	   );

	# Print the program header and read in command line options
	GetOptions(
		'D|daemon'		  => \$daemonFlag,
		'H|host=s'		  => \$host,
		'd|debug+'		  => \$debugLevel,
		'h|help'		  => \$helpFlag,
		'p|port=i'		  => \$port,
        'r|defaultrate=i' => \$defaultRate,
	   ) or abortWithUsage();

	# If the -h flag was given, just show the usage and quit
	helpMode() and exit if $helpFlag;

    # Build the configuration hash
    $config{host} = $host if $host;
    $config{port} = $port if $port;
    $config{daemon} = $daemonFlag;
    $config{debugLevel} = $debugLevel;
    $config{defaultRate} = $defaultRate if $defaultRate;

    # Create a new daemon object
	$server = new JobServer ( %config );

    # Add a simple log handler until I get the telnet one working
    my $tmplogger = sub {
        my ( $level, $format, @args ) = @_;
        printf STDERR "[$level] $format\n", @args;
    };
    $server->addLogHandler( 'tmplogger' => $tmplogger );

    # Start the server
	$server->start();
}


### FUNCTION: helpMode()
### Exit normally after printing the usage message
sub helpMode {
	pod2usage( -verbose => 1, -exitval => 0 );
}


### FUNCTION: abortWithUsage( $message )
### Abort the program showing usage message.
sub abortWithUsage {
	my $msg = @_ ? join('', @_) : "";

	if ( $msg ) {
		pod2usage( -verbose => 1, -exitval => 1, -message => "$msg" );
	} else {
		pod2usage( -verbose => 1, -exitval => 1 );
	}
}


#####################################################################
###	D A E M O N   C L A S S
#####################################################################
package JobServer;

BEGIN {
    use IO::Socket      qw{};
    use Data::Dumper    qw{Dumper};
    use Carp            qw{croak confess};

    use fields (
        'clients',              # Connected client objects
        'config',               # Configuration hash
		'listener',				# The listener socket
        'handlers',             # Client event handlers
        'jobs',                 # Mover jobs
		'totaljobs',			# Count of jobs processed
        'assignments',          # Jobs that have been assigned
        'users',                # Users in the queue
		'ratelimits',			# Hash of source cluster rates
		'jobcounts',			# Counts per cluster of running jobs
		'dbh',					# Database handle
       );

    use base qw{fields};
}


### Class globals

# Default configuration
our ( %DefaultConfig, $FetchClusterIdSql, $DefaultRateLimit );
INIT {

    # Default server configuration; this is merged with any config args the user
    # specifies in the call to the constructor.
    %DefaultConfig = (
        port         => 2789,           # Port to listen on
        host         => '0.0.0.0',      # Host to bind to
        listenqueue  => 5,              # Listen queue depth
        daemon       => 0,              # Daemonize or not?
        debugLevel   => 0,              # Debugging log level
        defaultrate  => 1,              # The default src cluster rate
       );

    # SQL used to create the source cluster id for users being moved.
    $FetchClusterIdSql = q{
        SELECT clusterid
        FROM clustertrack2
        WHERE userid = ?
    };

}

#
# Datastructures of class members:
#
# clients:     Hashref of connected clients, keyed by fdno
#
# jobs:        A hash of arrays of arrays:
#              {
#                <srcclusterid> => [ [<userid>, <destclusterid>], ... ],
#                ...
#              }
#
# users:       A hash index into the inner arrays of 'jobs', keyed by
#              userid.
#
# assignments: A hash of arrays; when a job is assigned to a mover, the
#              corresponding inner hashref of 'jobs' is moved into this hash,
#              keyed by the fdno of the mover responsible.
#
# handlers:    Hash of hashes; this is used to register callbacks for clients that
#              want to monitor the server, receiving log or debugging messages,
#              new job notifications, etc.
#
# totaljobs:   Count of total jobs added to the daemon.
#
# ratelimits:  Maximum number of jobs which can be run against source clusters,
#              keyed by clusterid. If a global rate limit has been set, this
#              hash also contains a special key 'global' to contain it.
#
# jobcounts:   Count of jobs running against source clusters, keyed by
#              source clusterid.

### (CONSTRUCTOR) METHOD: new( %config )
### Create a new JobServer object with the given I<config>.
sub new {
    my JobServer $self = shift;
    my %config = @_;

    $self = fields::new( $self ) unless ref $self;

    # Client and job queues
    $self->{clients}     = {};  # fd -> client obj
    $self->{jobs}        = {};  # pending jobs srcluster -> [ jobs ]
    $self->{users}       = {};  # by-userid hash of jobs (for uniquification)
    $self->{assignments} = {};  # fd -> job arrayref
    $self->{totaljobs}   = 0;   # Count of total jobs queued
    $self->{ratelimits}  = {};  # Rate limits by srcclusterid
    $self->{jobcounts}   = {};  # Count of jobs by srcclusterid

    # Merge the user-specified configuration with the defaults, with the user's
    # overriding.
    $self->{config}      =  {
        %DefaultConfig,
        %config,
    };                          # merge

    # The listener socket; gets set by start()
	$self->{listener}    =  undef;

    # CODE refs for handling various events. Keyed by event name, each subhash
    # contains registrations for event callbacks. Each subhash is keyed by the
    # fdno of the client that requested it, or an arbitrary string if the
    # handler belongs to something other than a client.
    $self->{handlers}    =  {
        debug        => {},
        log          => {},
    };

    # Database handle to the global to select source clusterids; set in start()
    $self->{dbh} = undef;

    return $self;
}



### METHOD: start()
### Start the event loop.
sub start {
    my JobServer $self = shift;

    # Connect to the database
    $self->{dbh} = LJ::get_dbh({raw=>1}, "master")
        or die "Can't get a master dbh: ", $DBI::errstr;

    # Start the listener socket
    my $listener = new IO::Socket::INET
        Proto       => 'tcp',
        LocalAddr   => $self->{config}{host},
        LocalPort   => $self->{config}{port},
        Listen      => $self->{config}{listenqueue},
        ReuseAddr   => 1,
        ReusePort   => 1,
        Blocking    => 0
            or die "new socket: $!";

    # Log the server startup, then daemonize if it's called for
    $self->logMsg( 'notice', "Server listening on %s:%d\n",
                   $listener->sockhost, $listener->sockport );
    $self->{listener} = $listener;
    $self->daemonize if $self->{config}{daemon};

	# I don't understand this design -- the Client class is where the event loop
	# is? Weird. Thanks to SPUD, though, for the example code.
	JobServer::Client->OtherFds( $listener->fileno => sub {$self->createClient} );
 	JobServer::Client->EventLoop();

    return 1;
}



### METHOD: createClient( undef )
### Listener socket readable callback. Accepts a new client socket and wraps a
### JobServer::Client around it.
sub createClient {
	my JobServer $self = shift;

    my (
        $csock,                 # Client socket
        $client,                # JobServer::Client object
        $fd,                    # File descriptor for client
       );

    # Get the client socket and set it nonblocking
    $csock = $self->{listener}->accept or return;
	$csock->blocking(0);
    $fd = fileno( $csock );

    $self->logMsg( 'info', 'Client %d connect: %s:%d',
                   $fd, $csock->peerhost, $csock->peerport );

    # Wrap a client object around it, tell it to watch for input, and send the
    # greeting.
    $client = JobServer::Client->new( $self, $csock );
	$client->watch_read( 1 );
    $client->write( "READY\r\n" );

    return $self->{clients}{$fd} = $client;
}


### METHOD: disconnectClient( $client=JobServer::Client[, $requeue] )
### Disconnect the specified I<client> from the server. If I<requeue> is true,
### the job belonging to the client (if any) will be put back into the queue of
### pending jobs.
sub disconnectClient {
    my JobServer $self = shift;
    my ( $client, $requeue ) = @_;

    my (
        $csock,                 # Client socket
        $fd,                    # Client's fdno
        $retask,                # Job that client was working on
       );

    # Stop further input from the socket
    $csock = $client->sock;
    $csock->shutdown( 0 ) if $csock->connected;
    $fd = fileno( $csock );
    $self->logMsg( 'info', "Client %d disconnect: %s:%d",
                   $fd, $csock->peerhost, $csock->peerport );

    # Remove any event handlers registered for the client
	$self->removeAllHandlers( $fd );

    # Re-queue any job that was assigned to the client
    if ( $requeue && ($retask = delete $self->{assignments}{$fd}) ) {
        $self->logMsg( 'info', "Re-adding job %d:%d to queue", @$retask );
        unshift @{$self->{jobs}}, $retask;
    }

    # Remove the client from our list
    delete $self->{clients}{ $fd };
    return "GOODBYE";
}


### METHOD: addJob( $userid, $destclustid )
### Add a job to move the user with the given I<userid> to the cluster with the
### specified I<destclustid>.
sub addJobs {
    my JobServer $self = shift;
    my @jobs = @_;

    my (
        @responses,
        $sth,
        $clusterid,
        $job,
        $userid,
        $dstclusterid,
       );

    # Iterate over job specifications
  JOB: for ( my $i = 0; $i <= $#jobs; $i++ ) {
        $job = $jobs[ $i ];
        ( $userid, $dstclusterid ) = @$job;

        # Check to be sure this job isn't already queued or in progress.
        if ( exists $self->{users}{$userid} ) {
            $self->debugMsg( 2, "Request for duplicate job %d:%d", @$job );
            $responses[$i] = "DUPLICATE JOB $userid:$dstclusterid";
            next JOB;
        }

        # Create the cluster id selection handle if it doesn't already exist,
        # aborting the current job if we're unable to do so.
        $sth ||= $self->getClusterIdLookupHandle
            or $responses[$i] = "ERR: database error: " . $self->{dbh}->errstr;
        next JOB unless $sth;

        # Fetch the source clusterid, append it to the job, and queue it
        if ( $sth->execute($userid) ) {

            # Fetch clusterid
            ( $clusterid ) = $sth->fetchrow_array;
            if ( $sth->err ) {
                $responses[$i] = "ERR: fetch clusterid failed: " . $sth->errstr;
                next JOB;
            }

            # Push the clusterid onto the job, queue it, and point the user
            # index at the job.
            push @$job, $clusterid;
            push @{$self->{jobs}{$clusterid}}, $job;
            $self->{users}{ $userid } = $job;

            $responses[$i] = "ADDED JOB ". ++$self->{totaljobs};
        } else {
            $responses[$i] = "ERR: query failed: " . $sth->errstr;
        }
    }

    return @responses;
}


### METHOD: getClusterIdLookupHandle( undef )
### Prepare a DBI statement handle for looking up the clusterid of a user.
sub getClusterIdLookupHandle {
    my JobServer $self = shift;

    # Prepare the handle and return it
    $self->debugMsg( 4, "Preparing clusterid lookup handle." );
    my $sth = $self->{dbh}->prepare( $FetchClusterIdSql )
        or $self->logMsg( 'error', 'prepare: %s: %s',
                          $FetchClusterIdSql, $self->{dbh}->errstr );

    return $sth;
}


### METHOD: getJob( $client=JobServer::Client )
### Fetch a job for the given I<client> and return it. If there are no pending
### jobs, returns the undefined value.
sub getJob {
    my JobServer $self = shift;
    my ( $client ) = @_ or croak "No client object";

    my (
        $fd,                    # Client's fdno
        $job,                   # Job arrayref
       );

    $fd = fileno( $client->{sock} );

    # Check for an unfinished assignment for this client
    if (( exists $self->{assignments}{ $fd } )) {
        $job = $self->{assignments}{ $fd };
        die "You didn't finish job ", join(':', @$job);
    }

    return $self->findNextJob( $fd );
}


### METHOD: findNextJob( undef )
### Find the next pending job from the queue that would read from a non-busy
### source cluster, as determined by the rate limits given to the server.
sub findNextJob {
    my JobServer $self = shift;
    my $fd = shift or return;

    my (
        $src,                   # Clusterid of a source
        $defrate,               # Default rate
        $rates,                 # Rate limits by clusterid
        $jobcounts,             # Counts of current jobs, by clusterid
        @candidates,            # Clusters with open slots
       );

    $defrate = $self->{config}{defaultRate};
    $rates = $self->{ratelimits};
    $jobcounts = $self->{jobcounts};

    # Find clusterids of clusters with open slots, returning the undefined value
    # if there are none.
    @candidates = grep {
        $jobcounts->{$_} < ($rates->{$_} || $defrate)
    } keys %{$self->{jobs}};
    return undef unless @candidates;

    # Pick a random cluster from the available list
    $src = $candidates[ int rand(@candidates) ];

    # Assign the next job from that cluster and return it
    return $self->assignJobFromCluster( $src, $fd );
}


### METHOD: assignJobFromCluster( $clusterid, $fdno )
### Assign the next job from the cluster with the specified I<clusterid> to the
### client with the given file descriptor I<fdno>.
sub assignJobFromCluster {
    my JobServer $self = shift;
    my ( $clusterid, $fdno ) = @_;

    # Grab a job from the cluster's queue and add it to the assignments table.
    my $job = $self->{assignments}{$fdno} = shift @{$self->{jobs}{$clusterid}};

    # Increment the job counter for that cluster and delete the queue if it's
    # empty.
    delete $self->{jobs}{$clusterid} if ! @{$self->{jobs}{$clusterid}};
    $self->{jobcounts}{$clusterid}++;

    return $job;
}


### METHOD: markUserReadonly( $userid )
### Mark the user with the given I<userid> read-only.
sub markUserReadonly {
    my JobServer $self = shift;
    my $userid = shift;

    # :TODO: Needs implementation

    return 1;
}


### METHOD: unmarkUserReadonly( $userid )
### Mark the user with the given I<userid> read-write.
sub unmarkUserReadonly {
    my JobServer $self = shift;
    my $userid = shift;

    # :TODO: Needs implementation

    return 1;
}


### METHOD: shutdown( $agent )
### Shut the server down.
sub shutdown {
    my JobServer $self = shift;
	my $agent = shift;

    # Stop incoming connections (:TODO: remove it from Danga::Socket?)
	$self->{listener}->close;

	# Clear jobs so no more get handed out while clients are closing
	$self->{jobs} = {};
	$self->{users} = {};
	$self->logMsg( 'notice', "Server shutdown by $agent" );

	# Close the db connection
	$self->{dbh}->disconnect;

	# Drop all clients
	foreach my $client ( @{$self->{clients}} ) {
		$client->write( "SERVER SHUTDOWN\r\n" );
		$self->disconnectClient( $client );
		$client->close;
	}

	exit;
}


### METHOD: removeAllHandlers( $key )
### Remove all event callbacks for the specified I<key>. Returns the number of
### handlers removed.
sub removeAllHandlers {
	my JobServer $self = shift;

	my $count = 0;
	foreach my $type ( keys %{$self->{handlers}} ) {
		my $method = sprintf 'remove%sHandler', uc $type;
		$count++ if $self->$method();
	}

	return $count;
}


### METHOD: addLogHandler( $key, \&code )
### Add a callback (I<code>) that handles log messages. The I<key> argument can
### be used to later remove the handler.
sub addLogHandler {
    my JobServer $self = shift;
    my ( $key, $code ) = @_;

    $self->{handlers}{log}{ $key } = $code;
}


### METHOD: removeLogHandler( $key )
### Remove and return the logging callback associated with the specified I<key>.
sub removeLogHandler {
    my JobServer $self = shift;
    my ( $key ) = @_;

    return delete $self->{handlers}{log}{ $key };
}


### METHOD: addDebugHandler( $key, \&code )
### Add a callback (I<code>) that handles log messages. The I<key> argument can
### be used to later remove the handler.
sub addDebugHandler {
    my JobServer $self = shift;
    my ( $key, $code ) = @_;

    $self->{handlers}{debug}{ $key } = $code;
}


### METHOD: removeDebugHandler( $key )
### Remove and return the debugging callback associated with the specified I<key>.
sub removeDebugHandler {
    my JobServer $self = shift;
    my ( $key ) = @_;

    return delete $self->{handlers}{debug}{ $key };
}





#####################################################################
###	' P R O T E C T E D '   M E T H O D S
#####################################################################


### METHOD: daemonize( undef )
### Double fork and become a good little daemon
sub daemonize {
    my JobServer $self = shift;

	$self->stubbornFork( 5 ) && exit 0;

	# Become session leader to detach from controlling tty
	POSIX::setsid() or croak "Couldn't become session leader: $!";

    # Fork again, ignore hangup to avoid reacquiring a controlling tty
    {
        local $SIG{HUP} = 'IGNORE';
        $self->stubbornFork( 5 ) && exit 0;
    }

	# Change working dir to the filesystem root, clear the umask
	chdir "/";
	umask 0;

	# Close standard file descriptors and reopen them to /dev/null
	close STDIN && open STDIN, "</dev/null";
	close STDOUT && open STDOUT, "+>&STDIN";
	close STDERR && open STDERR, "+>&STDIN";
}


### METHOD: stubbornFork( $maxTries )
###	Attempt to fork through errors
sub stubbornFork {
    my JobServer $self = shift;
	my $maxTries = shift || 5;

	my(
	   $pid,
	   $tries,
	  );

	$tries = 0;
  FORK: while ( $tries <= $maxTries ) {
		if (( $pid = fork )) {
			return $pid;
		} elsif ( defined $pid ) {
			return 0;
		} elsif ( $! =~ m{no more process} ) {
			sleep 5;
			next FORK;
		} else {
			die "Cannot fork: $!";
		}
	} continue {
		$tries++;
	}

	die "Failed to fork after $tries tries: $!";
}


### METHOD: debugMsg( $level, $format, @args )
### If the debug level is C<$level> or above, and there are debug handlers
### defined, call each of them at the specified level with the given printf
### C<$format> and C<@args>.
sub debugMsg {
	my JobServer $self = shift or confess "Not a function";
	my $level = shift;
	my $debugLevel = $self->{config}{debugLevel};
	return unless $level && $debugLevel >= abs $level;
    return unless %{$self->{handlers}{log}} || %{$self->{handlers}{debug}};

    my $message = shift;
    $message =~ s{[\r\n]+$}{};

	if ( $debugLevel > 1 ) {
		my $caller = caller;
		$message = "<$caller> $message";
	}

    # :TODO: Add handlers code
    for my $func ( values %{$self->{handlers}{debug}} ) { $func->( $message, @_ ) }
    $self->logMsg( 'debug', $message, @_ );
}


### METHOD: logMsg( $level, $format, @args )
### Call any log handlers that have been defined at the specified level with the
### given printf C<$format> and C<@args>.
sub logMsg {
	my $self = shift or confess "Not a function.";
    return () unless %{$self->{handlers}{log}};

	my (
		@args,
		$level,
		$objectName,
		$format,
	   );

	# Massage the format a bit to include the object it's coming from.
	$level = shift;
	$objectName = ref $self;
	$format = sprintf( '%s: %s', $objectName, shift() );
    $format =~ s{[\r\n]+$}{};

	# Turn any references or undefined values in the arglist into dumped strings
	@args = map {
        defined $_ ?
            (ref $_ ? Data::Dumper->Dumpxs([$_], [ref $_]) : $_) :
            '(undef)'
        } @_;

	# Call the logging callback
	for my $func ( values %{$self->{handlers}{log}} ) {
        $func->( $level, $format, @args );
    }
}




#####################################################################
###	C L I E N T   B A S E   C L A S S
#####################################################################
package JobServer::Client;

# Props to Junior for lots of this code, stolen largely from the SPUD server.

BEGIN {
    use Carp qw{croak confess};
    use base qw{Danga::Socket};
	use fields qw{server cmd_buf state};
}


our ( %CommandTable, $CommandPattern );

# Commands the server understands. Each entry should be paired with a method
# called cmd_<command_name>. The 'args' element contains a regexp for matching
# the command's arguments after whitespace-stripping on both sides; any
# capture-groups will be passed to the method as arguments. Commands which don't
# match the argument pattern will produce an error message. E.g., if the pattern
# for 'foo_bar' is /^(\w+)\s+(\d+)$/, then entering the command "foo_bar
# frobnitz 4" would call: ->cmd_foo_bar( "frobnitz", "4" ).
INIT {
    %CommandTable = (

        # Form: get_job
        get_job  => {
            help => "get a job (from mover)",
            args => qr{^$},
        },

        # Form: add_jobs <userid>:<dstclusterid>
        #       add_jobs <userid>:<dstclusterid>, <userid>:<dstclusterid>, ...
        add_jobs  => {
            help => "add one or more new jobs",
            args => qr{^((?:\d+:\d+\s*,\s*)*\d+:\d+)$},
        },

        source_counts => {
            help      => "dump pending jobs per source cluster",
            args      => qr{^$},
        },

        stop_moves => {
            help   => "stop all moves",
            args   => qr{^(all)?$},
        },

        is_moving => {
            help  => "check if a user is being moved",
            args  => qr{^$},
        },

        check_instance => {
            help       => "get the random instance string for this mover",
            args       => qr{^$},
        },

        list_jobs => {
            help  => "list internal state",
            args  => qr{^$},
        },

        set_rate => {
            help     => "Set the rate for a given source cluster or for all clusters",
            args     => qr{^(\d+)(?:[:\s]+(\d+))?$},
        },

        finish => {
            help     => "request authorization to complete a move job",
            args     => qr{^(\d+)[:\s]+(\d+)$},
        },

        quit     => {
            help => "disconnect from the server",
            args => qr{^$},
        },

        shutdown => {
            help => "shut the server down",
            args => qr{^$},
        },

        help     => {
            help => "show this help",
            args => qr{^$},
        },
       );

    # Pattern to match command words
    $CommandPattern = join '|', keys %CommandTable;
    $CommandPattern = qr{^($CommandPattern)$};
}


### Create a new JobServer::Client object for the given I<socket>.
sub new {
    my JobServer::Client $self = shift;
    my $server = shift or confess "no server argument";
    my $sock = shift or confess "no socket argument";

    $self = fields::new( $self ) unless ref $self;
    $self->SUPER::new( $sock );

    $self->{server} = $server;
    $self->{cmd_buf} = [];      # Queue of pending commands
    $self->{state} = 'new';

    return $self;
}

### Readable event callback -- read input from the client and append it to the
### read buffer. Then peel lines off the read buffer and send them to the line
### processor.
sub event_read {
    my JobServer::Client $self = shift;

    my $bref = $self->read( 1024 );
    return $self->{server}->disconnectClient( $self, 1 ) unless defined $bref;
    $self->{read_buf} .= $$bref;

    while ($self->{read_buf} =~ s/^(.+?)\r?\n//) {
        my $line = $1;
        my $output = $self->processLine( $line );
        $self->write( "$output\r\n" ) if $output;
    }

}


sub sock {
	my JobServer::Client $self = shift;
	return $self->{sock};
}


sub event_err {
	my JobServer::Client $self = shift;
	$self->close;
}

sub event_hup {
	my JobServer::Client $self = shift;
	$self->close;
}


sub debugMsg {
    my JobServer::Client $self = shift;
    $self->{server}->debugMsg( @_ );
}


sub logMsg {
    my JobServer::Client $self = shift;
    $self->{server}->logMsg( @_ );
}


# Command dispatcher
sub processLine {
	my JobServer::Client $self = shift;
    my $line = shift or return undef;

    my (
        $reply,                 # Reply to send back to client
        $cmd,                   # Command word
        $args,                  # Argument string
        $argpat,                # Argument-parsing pattern
        @args,                  # Parsed arguments
        $method,                # Command method to call
       );

	# Split the line into command and argument string
    ( $cmd, $args ) = split /\s+/, $line, 2;
    $args ||= '';

    $self->debugMsg( 5, "Command table is: %s", \%CommandTable );
    $self->debugMsg( 4, "Matching '%s' against command table pattern %s",
                     $cmd, $CommandPattern );

	# If it's a command in the command table, dispatch to the appropriate
	# command handler after parsing any arguments.
    if ( $cmd =~ $CommandPattern ) {
        $method = "cmd_$1";
        $argpat = $CommandTable{ $1 }{args};

        # Parse command arguments
        if ( @args = ($args =~ $argpat) ) {

            # If the pattern didn't contain captures, throw away the args
            @args = () unless ( @+ > 1 );

            eval { $reply = $self->$method(@args) };
            if ( $@ ) { $reply = $self->error( $@ ) }
        }

        # Valid command, but bad args
        else {
            $reply = $self->error( "Malformed command args for '$cmd': '$args'." );
        }
    }

    # Invalid command
    else {
        $reply = $self->error( "Invalid or malformed command '$cmd'" );
    }

    return $reply;
}


### METHOD: error( @msg )
### Build an error message from the given I<msg> parts and log it at level
### 'error', then return an error message appropriate to send to the client.
sub error {
    my JobServer::Client $self = shift;
    my $msg = @_ ? join('', @_) : "Unknown error";

    # Remove up to 2 newlines
    chomp( $msg ); chomp( $msg );

    $self->{state} = 'error';
    $self->logMsg( "error", "[Client %s:%d] ERR: %s",
                   $self->{sock}->peerhost,
                   $self->{sock}->peerport,
                   $msg,
                  );

    $msg =~ s{at \S+ line \d+\..*}{};
    return "ERR: $msg";
}


#####################################################################
###	C O M M A N D   M E T H O D S
#####################################################################

### METHOD: cmd_get_job( undef )
### Command handler for the C<get_job> command.
sub cmd_get_job {
	my JobServer::Client $self = shift;

    my $job = $self->{server}->getJob( $self )
        or return "IDLE";

    return sprintf "JOB: %d:%d", @$job[0..1];
}


### METHOD: cmd_add_jobs( $argstring )
### Command handler for the C<add_job> command.
sub cmd_add_jobs {
	my JobServer::Client $self = shift;
    my $argstring = shift or return;

    # Turn the argument into an array of arrays
    my @tuples = map {
        [ split /:/, $_ ]
    } split /\s*,\s*/, $argstring;


    my @responses = $self->{server}->addJobs( @tuples );
    return join( "\r\n", @responses );
}


### METHOD: cmd_source_counts( undef )
### Command handler for the C<source_counts> command.
sub cmd_source_counts {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_stop_moves( undef )
### Command handler for the C<stop_moves> command.
sub cmd_stop_moves {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_is_moving( undef )
### Command handler for the C<is_moving> command.
sub cmd_is_moving {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_check_instance( undef )
### Command handler for the C<check_instance> command.
sub cmd_check_instance {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_list_jobs( undef )
### Command handler for the C<list_jobs> command.
sub cmd_list_jobs {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}


### METHOD: cmd_set_rate( undef )
### Command handler for the C<set_rate> command.
sub cmd_set_rate {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}


### METHOD: cmd_finish( undef )
### Command handler for the C<finish> command.
sub cmd_finish {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_help( undef )
### Command handler for the C<help> command.
sub cmd_help {
	my JobServer::Client $self = shift;
    return $self->error( "Unimplemented command." );
}

### METHOD: cmd_quit( undef )
### Command handler for the C<quit> command.
sub cmd_quit {
    my JobServer::Client $self = shift;

    my $msg = $self->{server}->disconnectClient( $self, 1 );
    $self->write( "$msg\r\n" );
    $self->close;

    return "";
}


### METHOD: cmd_shutdown( undef )
### Command handler for the C<shutdown> command.
sub cmd_shutdown {
    my JobServer::Client $self = shift;

	my $strself = sprintf( '%s:%d',
						   $self->{sock}->peerhost,
						   $self->{sock}->peeraddr );
    my $msg = $self->{server}->shutdown( $strself );
    $self->write( "$msg\r\n" );
    $self->close;

    return "";
}


