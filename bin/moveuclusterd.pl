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

=item -s, --lockscale=INTEGER

Set the lock-scaling factor to I<INTEGER>. The lock scaling factor is used to
decide how many users to lock per source cluster. The value is a multiple 

:TODO: finish documenting this.

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
    $VERSION    = do { my @r = (q$Revision$ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    $RCSID      = q$Id$;

    # Define some constants
    use constant TRUE   => 1;
    use constant FALSE  => 0;

    use lib "$ENV{LJHOME}/cgi-bin";
    require "ljlib.pl";

    # Modules
    use Carp                qw{croak confess};
    use Getopt::Long        qw{GetOptions};
    use Pod::Usage          qw{pod2usage};

    Getopt::Long::Configure( 'bundling' );
}


###############################################################################
### C O N F I G U R A T I O N   G L O B A L S
###############################################################################

### Main body
MAIN: {
    my (
        $debugLevel,            # Debugging level to set in server
        $helpFlag,              # User requested help?
        $daemonFlag,            # Background after starting?
        $defaultRate,           # Default src cluster rate cmdline setting
        $server,                # JobServer object
        %config,                # JobServer configuration
        $port,                  # Port to listen on
        $host,                  # Address to listen on
        $lockScale,             # Lock scaling factor
       );

    # Print the program header and read in command line options
    GetOptions(
        'D|daemon'        => \$daemonFlag,
        'H|host=s'        => \$host,
        'd|debug+'        => \$debugLevel,
        'h|help'          => \$helpFlag,
        'p|port=i'        => \$port,
        'r|defaultrate=i' => \$defaultRate,
        's|lockscale=i'   => \$lockScale,
       ) or abortWithUsage();

    # If the -h flag was given, just show the usage and quit
    helpMode() and exit if $helpFlag;

    # Build the configuration hash
    $config{host} = $host if $host;
    $config{port} = $port if $port;
    $config{daemon} = $daemonFlag;
    $config{debugLevel} = $debugLevel || 0;
    $config{defaultRate} = $defaultRate if $defaultRate;
    $config{lockScale} = $lockScale if $lockScale;

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
### D A E M O N   C L A S S
#####################################################################
package JobServer;

BEGIN {
    use IO::Socket      qw{};
    use Data::Dumper    qw{Dumper};
    use Carp            qw{croak confess};
    use Time::HiRes     qw{gettimeofday tv_interval};

    use fields (
        'clients',              # Connected client objects
        'config',               # Configuration hash
        'listener',             # The listener socket
        'handlers',             # Client event handlers
        'jobs',                 # Mover jobs
        'totaljobs',            # Count of jobs processed
        'assignments',          # Jobs that have been assigned
        'users',                # Users in the queue
        'ratelimits',           # Cached cluster ratelimits
        'raterules',            # Rules for building ratelimit table
        'jobcounts',            # Counts per cluster of running jobs
        'starttime',            # Server startup epoch time
       );

    use lib "$ENV{LJHOME}/cgi-bin";
    require 'ljlib.pl';

    use base qw{fields};
}


### Class globals

# Default configuration
our ( %DefaultConfig );

INIT {

    # Default server configuration; this is merged with any config args the user
    # specifies in the call to the constructor. Most of these correspond with
    # command-line flags, so see that section of the POD header for more
    # information.
    %DefaultConfig = (
        port         => 2789,           # Port to listen on
        host         => '0.0.0.0',      # Host to bind to
        listenQueue  => 5,              # Listen queue depth
        daemon       => 0,              # Daemonize or not?
        debugLevel   => 0,              # Debugging log level
        defaultRate  => 1,              # The default src cluster rate
        lockScale    => 3,              # Scaling factor for locking users
       );

    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
}

#
# Datastructures of class members:
#
# clients:     Hashref of connected clients, keyed by fdno
#
# jobs:        A hash of arrays of JobServer::Job objects:
#              {
#                <srcclusterid> => [ $job1, $job2, ... ],
#                ...
#              }
#
# users:       A hash index into the inner arrays of 'jobs', keyed by
#              userid.
#
# assignments: A hash of arrays; when a job is assigned to a mover, the
#              corresponding JobServer::Job is moved into this hash,
#              keyed by the fdno of the mover responsible.
#
# handlers:    Hash of hashes; this is used to register callbacks for clients that
#              want to monitor the server, receiving log or debugging messages,
#              new job notifications, etc.
#
# totaljobs:   Count of total jobs added to the daemon.
#
# raterules:   Maximum number of jobs which can be run against source clusters,
#              keyed by clusterid. If a global rate limit has been set, this
#              hash also contains a special key 'global' to contain it.
#
# ratelimits:  Cached ratelimits for clusters -- this is rebuilt whenever a
#              ratelimit rule is added, and is partially rebuilt when new jobs
#              are added.
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
    $self->{users}       = {};  # by-userid hash of jobs
    $self->{assignments} = {};  # fd -> job arrayref
    $self->{totaljobs}   = 0;   # Count of total jobs added
    $self->{raterules}   = {};  # User-set rate-limit rules
    $self->{ratelimits}  = {};  # Cached rate limits by srcclusterid
    $self->{jobcounts}   = {};  # Count of jobs by srcclusterid

    # Merge the user-specified configuration with the defaults, with the user's
    # overriding.
    $self->{config}      =  {
        %DefaultConfig,
        %config,
    };                          # merge

    # These two get set by start()
    $self->{listener}    = undef;
    $self->{starttime}   = undef;

    # CODE refs for handling various events. Keyed by event name, each subhash
    # contains registrations for event callbacks. Each subhash is keyed by the
    # fdno of the client that requested it, or an arbitrary string if the
    # handler belongs to something other than a client.
    $self->{handlers}    =  {
        debug        => {},
        log          => {},
    };

    return $self;
}



### METHOD: start()
### Start the event loop.
sub start {
    my JobServer $self = shift;

    # Start the listener socket
    my $listener = new IO::Socket::INET
        Proto       => 'tcp',
        LocalAddr   => $self->{config}{host},
        LocalPort   => $self->{config}{port},
        Listen      => $self->{config}{listenQueue},
        ReuseAddr   => 1,
        Blocking    => 0
            or die "new socket: $!";

    # Log the server startup, then daemonize if it's called for
    $self->logMsg( 'notice', "Server listening on %s:%d\n",
                   $listener->sockhost, $listener->sockport );
    $self->{listener} = $listener;
    $self->daemonize if $self->{config}{daemon};

    # Remember the startup time
    $self->{starttime} = time;

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
    $client->write( "Ready.\r\n" );

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
        $job,                   # Job that client was working on
       );

    # Stop further input from the socket
    $csock = $client->sock;
    $csock->shutdown( 0 ) if $csock->connected;
    $fd = fileno( $csock );
    $self->logMsg( 'info', "Client %d disconnect: %s:%d",
                   $fd, $csock->peerhost, $csock->peerport );

    # Remove any event handlers registered for the client
    $self->removeAllHandlers( $fd );
    $self->unassignJobForClient( $fd );

    # Remove the client from our list
    delete $self->{clients}{ $fd };
}


### METHOD: addJobs( @jobs=JobServer::Job )
### Add a job to move the user with the given I<userid> to the cluster with the
### specified I<dstclustid>.
sub addJobs {
    my JobServer $self = shift;
    my @jobs = @_;

    my (
        @responses,
        $clusterid,
        $job,
        $userid,
        $srcclusterid,
        $dstclusterid,
       );

    # Iterate over job specifications
  JOB: for ( my $i = 0; $i <= $#jobs; $i++ ) {
        $job = $jobs[ $i ];
        $self->debugMsg( 5, "Adding job: %s", $job->stringify );

        ( $userid, $clusterid ) = ( $job->userid, $job->srcclusterid );

        # Check to be sure this job isn't already queued or in progress.
        if ( $self->{users}{$userid} ) {
            $self->debugMsg( 2, "Request for duplicate job %s", $job->stringify );
            $responses[$i] = "Duplicate job for userid $userid";
            next JOB;
        }

        # Queue the job and point the user index at it.
        $self->{jobs}{$clusterid} ||= [];
        push @{$self->{jobs}{$clusterid}}, $job;
        $self->{users}{ $userid } = $job;
        $self->{jobcounts}{$clusterid} ||= 0;

        $responses[$i] = "Added job ". ++$self->{totaljobs};
    }

    $self->prelockSomeUsers;

    return @responses;
}


### METHOD: prelockSomeUsers( undef )
### Mark some of the users in the queues as read-only so the movers don't need
### to do so before moving. Only marks a portion of each queue so as to not
### inconvenience users.
sub prelockSomeUsers {
    my JobServer $self = shift;

    my $start = [gettimeofday()];

    my (
        $jobcount,              # Number of jobs queued for a cluster
        $rate,                  # Rate for the cluster in question
        $target,                # Number of queued jobs we'd like to be locked
        $lockcount,             # Number of users locked
        $scale,                 # Lock scaling factor
        $clients,               # Number of currently-connected clients
        $jobs,                  # Job queue per cluster
       );

    # Twiddle some database bits out in magic voodoo land
    LJ::start_request();

    # Set the scaling factor -- this is a command-line setting that affects how
    # deep the queue is locked per source cluster.
    $scale = $self->{config}{lockScale};

    # Iterate over all the queues we have by cluster
  CLUSTER: foreach my $clusterid ( keys %{$self->{jobs}} ) {
        $rate = $self->getClusterRateLimit( $clusterid );
        $target = $rate * $scale;

        # Now iterate partway into the queue of jobs for the cluster, locking
        # some users if there are some that need locking
        $jobs = $self->{jobs}{ $clusterid };
      JOB: for ( my $i = 0; $i <= $target; $i++ ) {

            # If there are fewer jobs than the target number to be locked, skip
            # to the next cluster
            next CLUSTER if $i > $#$jobs;

            # Skip jobs that're already prelocked, or try to lock. If locking
            # fails, assume there's some database problems and don't try to
            # prelock any more until next time.
            next JOB if $jobs->[$i]->isPrelocked;
            $jobs->[$i]->prelock or last CLUSTER;
        }
    }

    $self->debugMsg( 4, "Prelock time: %0.5fs", tv_interval($start) );
    return $lockcount;
}


### METHOD: getClusterRateLimit( $clusterid )
### Return the number of connections which can be reading from the cluster with
### the given I<clusterid>.
sub getClusterRateLimit {
    my JobServer $self = shift;
    my $clusterid = shift or confess "No clusterid";

    # Swap the next two lines to make the 'global' rate override those of
    # specific clusters.
    return $self->{raterules}{ $clusterid } if exists $self->{raterules}{ $clusterid };
    return $self->{raterules}{global} if exists $self->{raterules}{global};
    return $self->{config}{defaultRate};
}


### METHOD: getClusterRateLimits( undef )
### Return the rate limits for all known clusters as a hash (or hashref if
### called in scalar context) keyed by clusterid.
sub getClusterRateLimits {
    my JobServer $self = shift;

    # (Re)build the rates table as necessary
    unless ( %{$self->{ratelimits}} ) {
        for my $clusterid ( keys %{$self->{jobs}} ) {
            $self->{ratelimits}{ $clusterid } =
                $self->getClusterRateLimit( $clusterid );
        }
    }

    return wantarray ? %{$self->{ratelimits}} : $self->{ratelimits};
}


### METHOD: setClusterRateLimit( $clusterid, $rate )
### Set the rate limit for the cluster with the given I<clusterid> to I<rate>.
sub setClusterRateLimit {
    my JobServer $self = shift;
    my ( $clusterid, $rate ) = @_;

    die "No clusterid" unless $clusterid;
    die "No ratelimit" unless defined $rate && int($rate) == $rate;

    # Set the new rule and trash the precalculated table
    $self->{raterules}{ $clusterid } = $rate;
    %{$self->{ratelimits}} = ();

    return "Rate limit for cluster $clusterid set to $rate";
}


### METHOD: setGlobalRateLimit( $rate )
### Set the rate limit for clusters that don't have an explicit ratelimit to
### I<rate>.
sub setGlobalRateLimit {
    my JobServer $self = shift;
    my $rate = shift;
    die "No ratelimit" unless defined $rate && int($rate) == $rate;

    # Set the global rule and clear out the cached table to rebuild it next time
    # it's used
    $self->{raterules}{global} = $rate;
    %{$self->{ratelimits}} = ();

    return "Global rate limit set to $rate";
}


### METHOD: getJob( $client=JobServer::Client )
### Fetch a job for the given I<client> and return it. If there are no pending
### jobs, returns the undefined value.
sub getJob {
    my JobServer $self = shift;
    my ( $client ) = @_ or confess "No client object";

    my (
        $fd,                    # Client's fdno
        $job,                   # Job arrayref
       );

    $fd = $client->fdno or confess "No file descriptor?!?";
    $self->unassignJobForClient( $fd );

    return $self->assignNextJob( $fd );
}


### METHOD: assignNextJob( $fdno )
### Find the next pending job from the queue that would read from a non-busy
### source cluster, as determined by the rate limits given to the server. If one
### is found, assign it to the client associated with the given file descriptor
### I<fdno>. Returns the reply to be sent to the client.
sub assignNextJob {
    my JobServer $self = shift;
    my $fd = shift or return;

    my (
        $src,                   # Clusterid of a source
        $rates,                 # Rate limits by clusterid
        $jobcounts,             # Counts of current jobs, by clusterid
        @candidates,            # Clusters with open slots
       );

    $rates = $self->getClusterRateLimits;
    $jobcounts = $self->{jobcounts};

    # Find clusterids of clusters with open slots, returning the undefined value
    # if there are none.
    @candidates = grep {
        $jobcounts->{$_} < $rates->{$_}
    } keys %{$self->{jobs}};
    return undef unless @candidates;

    # Pick a random cluster from the available list
    $src = $candidates[ int rand(@candidates) ];
    $self->debugMsg( 4, "Assigning job for cluster %d (%d of %d)",
                     $src, $jobcounts->{$src} + 1, $rates->{$src} );

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

    # If there are more jobs for this queue, and the next job in the queue isn't
    # prelocked, lock some more
    $self->prelockSomeUsers
        if exists $self->{jobs}{$clusterid}
            && ! $self->{jobs}{$clusterid}[0]->isPrelocked;

    return $job;
}


### METHOD: unassignJobForClient( $fdno )
### Unassign the job currently assigned to the client associated with the given
### I<fdno>.
sub unassignJobForClient {
    my JobServer $self = shift;
    my $fdno = shift or confess "No client fdno";
    my $requeue = shift || '';

    my (
        $job,
        $src,
       );

    # If there is a currently assigned job, we have work to do
    if (( $job = delete $self->{assignments}{$fdno} )) {
        $src = $job->srcclusterid;

        unless ( $job->isFinished ) {

            # If re-queueing of dropped jobs is enabled, requeue it
            if ( $requeue ) {
                $self->logMsg( 'info', "Re-adding job %s to queue", $job->stringify );
                $self->{jobs}{ $job->srcclusterid } ||= [];
                unshift @{$self->{jobs}{ $job->srcclusterid }}, $job;
            }

            # Free up a slot on the source
            $self->debugMsg( 3, "Client %d dropped job %s", $fdno, $job->stringify );
        }

        # Delete the user's job and decrement the job count for the cluster the
        # job belonged to
        delete $self->{users}{ $job->userid };
        $self->{jobcounts}{ $src }--;
        $self->debugMsg( 3, "Cluster %d now has %d clients",
                         $src, $self->{jobcounts}{ $src } );
    }

    return $job;
}


### METHOD: getJobForUser( $userid )
### Return the job associated with a given userid.
sub getJobForUser {
    my JobServer $self = shift;
    my $userid = shift or confess "No userid specified";

    return $self->{users}{ $userid };
}


### METHOD: stopAllJobs( $client=JobServer::Client )
### Stop all pending and currently-assigned jobs.
sub stopAllJobs {
    my JobServer $self = shift;
    my $client = shift or confess "No client object";

    $self->stopNewJobs( $client );
    $self->logMsg( 'notice', "Clearing currently-assigned jobs." );
    %{$self->{assignments}} = ();

    return "Cleared all jobs.";
}


### METHOD: stopNewJobs( $client=JobServer::Client )
### Stop assigning pending jobs.
sub stopNewJobs {
    my JobServer $self = shift;
    my $client = shift or confess "No client object";

    $self->logMsg( 'notice', "Clearing pending jobs." );
    %{$self->{jobs}} = ();

    return "Cleared pending jobs.";
}


### METHOD: requestJobFinish( $client=JobServer::Client, $userid, $srcclusterid, $dstclusterid )
### Request authorization to finish a given job.
sub requestJobFinish {
    my JobServer $self = shift;
    my ( $client, $userid, $srcclusterid, $dstclusterid ) = @_;

    my (
        $fdno,                  # The client's fdno
        $job,                   # The client's currently assigned job
       );

    # Fetch the fdno of the client and try to get the job object they were last
    # assigned. If it doesn't exist, all jobs are stopped or something else has
    # happened, so advise the client to abort.
    $fdno = $client->fdno;
    if ( ! exists $self->{assignments}{$fdno} ) {
        $self->logMsg( 'warn', "Client $fdno: finish on unassigned job" );
        return undef;
    }

    # If the job the client was last assigned doesn't match the userid they've
    # specified, abort.
    $job = $self->{assignments}{$fdno};
    if ( $job->userid != $userid ) {
        $self->logMsg( 'warn', "Client %d: finish for non-assigned job %s",
                       $fdno, $job->stringify );
        return undef;
    }

    # Otherwise mark the job as finished and advise the client that they can
    # proceed.
    $job->finishTime( time );
    $self->debugMsg( 2, 'Client %d finishing job %s',
                     $fdno, $job->stringify );

    return "Go ahead with job " . $job->stringify;
}



### METHOD: getJobList( undef )
### Return a hashref of job stats. The hashref will contain three arrays: the
### 'queued_jobs' array contains a line describing how many jobs are queued for
### each source cluster, the 'assigned_jobs' array contains a line per client
### that's currently moving a user, and the 'footers' array contains some lines
### of overall statistics about the server.
sub getJobList {
    my JobServer $self = shift;

    my (
        %stats,                 # The returned job stats
        $queuedCount,           # Number of queued jobs
        $assignedCount,         # Number of jobs currently assigned
        $job,                   # Job object iterator
        $rates,                 # Rate-limit table
       );

    %stats = ( queued_jobs => [], assigned_jobs => [], footer => [] );
    $queuedCount = $assignedCount = 0;
    $rates = $self->getClusterRateLimits;

    # The first sublist: queued jobs
    foreach my $clusterid ( sort keys %{$self->{jobs}} ) {
        push @{$stats{queued_jobs}},
            sprintf( "%3d: %5d jobs queued @ limit %d",
                     $clusterid,
                     scalar @{$self->{jobs}{$clusterid}},
                     $rates->{$clusterid} );
        $queuedCount += scalar @{$self->{jobs}{$clusterid}};
    }

    # Second sublist: assigned jobs
    foreach my $fdno ( sort keys %{$self->{assignments}} ) {
        $job = $self->{assignments}{$fdno};
        push @{$stats{assigned_jobs}},
            sprintf( "%3d: working on moving %7d from %3d to %3d",
                     $fdno, $job->userid, $job->srcclusterid,
                     $job->dstclusterid );
        $assignedCount++;
    }

    # Append the footer lines
    push @{$stats{footer}},
        sprintf( "  %d queued jobs, %d assigned jobs for %d clusters",
                 $queuedCount, $assignedCount, scalar keys %{$self->{jobs}} );
    push @{$stats{footer}},
        sprintf( "  %d of %d total jobs assigned since %s (%0.1f/s)",
                 $self->{totaljobs} - $queuedCount,
                 $self->{totaljobs},
                 scalar localtime($self->{starttime}),
                 (time - $self->{starttime}) / ($self->{totaljobs}||0.005)
                );

    return \%stats;
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
    $self->logMsg( 'notice', "Server shutdown by %s", $agent->stringify );

    # Drop all clients
    foreach my $client ( values %{$self->{clients}} ) {
        $client->write( "Server shutdown.\r\n" );
        $client->close;
    }

    exit;
}


### Handler methods

### METHOD: removeAllHandlers( $key )
### Remove all event callbacks for the specified I<key>. Returns the number of
### handlers removed.
sub removeAllHandlers {
    my JobServer $self = shift;

    my $count = 0;
    foreach my $type ( keys %{$self->{handlers}} ) {
        my $method = sprintf 'remove%sHandler', ucfirst $type;
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

    no warnings 'uninitialized';
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

    no warnings 'uninitialized';
    return delete $self->{handlers}{debug}{ $key };
}





#####################################################################
### ' P R O T E C T E D '   M E T H O D S
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
### Attempt to fork through errors
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
### J O B   C L A S S
#####################################################################
package JobServer::Job;
use strict;

BEGIN {
    use Carp qw{croak confess};

    use lib "$ENV{LJHOME}/cgi-bin";
    require 'ljlib.pl';
    require 'ljconfig.pl';

    use fields (
        'server',               # The server this job belongs to
        'userid',               # The userid of the user to move
        'srcclusterid',         # The cluster id of the source cluster
        'dstclusterid',         # Cluster id of the destination cluster
        'prelocktime',          # Epoch time of prelock, 0 if not prelocked
        'finishtime',           # Epoch time of server finish authorization
       );
}


### Class globals
our ( $ReadOnlyCapBit );

INIT {
    # Find the readonly cap class, complain if not found
    $ReadOnlyCapBit = undef;

    # Find the moveinprogress bit from the caps hash
    foreach my $bit ( keys %LJ::CAP ) {
        next unless exists $LJ::CAP{$bit}{_name};
        if ( $LJ::CAP{$bit}{_name} eq '_moveinprogress' &&
             $LJ::CAP{$bit}{readonly} == 1 )
        {
            $ReadOnlyCapBit = $bit;
            last;
        }
    }

    die "Cannot mark user readonly without a ReadOnlyCapBit. Check %LJ::CAP"
        unless $ReadOnlyCapBit;

}


### (CONSTRUCTOR) METHOD: new( [$userid, $srcclusterid, $dstclusterid )
### Create and return a new JobServer::Job object.
sub new {
    my JobServer::Job $self = shift;
    my $server = shift or confess "no server object";

    $self = fields::new( $self ) unless ref $self;

    # Split instance vars from a string with a colon in the second or later
    # position
    if ( index($_[0], ':') > 0 ) {
        @{$self}{qw{userid srcclusterid dstclusterid}} =
            split /:/, $_[0], 3;
    }

    # Allow list arguments as well
    else {
        @{$self}{qw{userid srcclusterid dstclusterid}} = @_;
    }

    $self->{server} = $server;
    $self->{prelocktime} = 0;
    $self->{finishtime} = 0;

    return $self;
}


### METHOD: userid( [$newuserid] )
### Get/set the job's userid.
sub userid {
    my JobServer::Job $self = shift;
    $self->{userid} = shift if @_;
    return $self->{userid};
}


### METHOD: srcclusterid( [$newsrcclusterid] )
### Get/set the job's srcclusterid.
sub srcclusterid {
    my JobServer::Job $self = shift;
    $self->{srcclusterid} = shift if @_;
    return $self->{srcclusterid};
}


### METHOD: dstclusterid( [$newdstclusterid] )
### Get/set the job's dstclusterid.
sub dstclusterid {
    my JobServer::Job $self = shift;
    $self->{dstclusterid} = shift if @_;
    return $self->{dstclusterid};
}


### METHOD: stringify( undef )
### Return a scalar containing the stringified representation of the job.
sub stringify {
    my JobServer::Job $self = shift;
    return sprintf '%d:%d:%d', @{$self}{'userid', 'srcclusterid', 'dstclusterid'};
}


### METHOD: prelock( undef )
### Mark the user in this job read-only and set the prelocktime.
sub prelock {
    my JobServer::Job $self = shift;

    my $rval = LJ::update_user( $self->{userid},
                                {raw => "caps = caps | (1<<$ReadOnlyCapBit)"} );

    if ( $rval ) {
        $self->{prelocktime} = time;
        $self->{server}->debugMsg( 4, q{Prelocked user %d}, $self->{userid} );
    } else {
        $self->{server}->logMsg( 'warn', q{Couldn't prelock user %d: %s},
                                 $self->{userid}, $DBI::errstr );
    }

    return $self->{prelocktime};
}


### METHOD: prelocktime( [$newprelocktime] )
### Get/set the epoch time when the user record corresponding to the job's
### C<userid> was set read-only.
sub prelocktime {
    my JobServer::Job $self = shift;
    $self->{prelocktime} = shift if @_;
    return $self->{prelocktime};
}


### METHOD: secondsSinceLock( undef )
### Return the number of seconds since the job's user was prelocked, or 0 if the
### user isn't prelocked.
sub secondsSinceLock {
    my JobServer::Job $self = shift;
    return 0 unless $self->{prelocktime};
    return time - $self->{prelocktime};
}


### METHOD: isPrelocked( undef )
### Returns a true value if the user corresponding to the job has already been
### marked read-only.
sub isPrelocked {
    my JobServer::Job $self = shift;
    return $self->{prelocktime} != 0;
}


### METHOD: finishTime( [$newtime] )
### Returns the epoch time when the job was 'finished'.
sub finishTime {
    my JobServer::Job $self = shift;
    $self->{finishtime} = shift if @_;
    return $self->{finishtime};
}


### METHOD: secondsSinceFinish( undef )
### Returns the number of seconds that have elapsed since the job was
### 'finished'.
sub secondsSinceFinish {
    my JobServer::Job $self = shift;
    return 0 unless $self->{finishtime};
    return time - $self->{finishtime};
}


### METHOD: isFinished( undef )
### Returns a true value if the mover has requested authorization from the
### jobserver to finish the job.
sub isFinished {
    my JobServer::Job $self = shift;
    return $self->{finishtime} != 0;
}


### METHOD: debugMsg( $level, $format, @args )
### Send a debugging message to the server this job belongs to.
sub debugMsg {
    my JobServer::Job $self = shift;
    $self->{server}->debugMsg( @_ );
}


### METHOD: logMsg( $type, $format, @args )
### Send a log message to the server this job belongs to.
sub logMsg {
    my JobServer::Job $self = shift;
    $self->{server}->logMsg( @_ );
}





#####################################################################
### C L I E N T   B A S E   C L A S S
#####################################################################
package JobServer::Client;

# Props to Junior for lots of this code, stolen largely from the SPUD server.

BEGIN {
    use Carp qw{croak confess};
    use base qw{Danga::Socket};
    use fields qw{server state read_buf};
}


our ( $Tuple, %CommandTable, $CommandPattern );

INIT {

    # Pattern for matching job-spec tuples of the form:
    #   <userid>:<srcclusterid>:<dstclusterid>
    $Tuple = qr{\d+:\d+:\d+};

    # Commands the server understands. Each entry should be paired with a method
    # called cmd_<command_name>. The 'args' element contains a regexp for
    # matching the command's arguments after whitespace-stripping on both sides;
    # any capture-groups will be passed to the method as arguments. Commands
    # which don't match the argument pattern will produce an error
    # message. E.g., if the pattern for 'foo_bar' is /^(\w+)\s+(\d+)$/, then
    # entering the command "foo_bar frobnitz 4" would call:
    #   ->cmd_foo_bar( "frobnitz", "4" )
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
            form => "<userid>:<srcclusterid>:<dstclusterid>[, ...]",
            args => qr{^((?:$Tuple\s*,\s*)*$Tuple)$},
        },

        source_counts => {
            help      => "dump pending jobs per source cluster",
            args      => qr{^$},
        },

        stop_moves => {
            help   => "stop all moves",
            form   => "[all]",
            args   => qr{^(all)?$},
        },

        is_moving => {
            help  => "check to see if a user is being moved",
            form  => "<userid>",
            args  => qr{^(\d+)$},
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
            form     => "<globalrate> or <srcclusterid>:<rate>",
            args     => qr{^(\d+)(?:[:\s]+(\d+))?\s*$},
        },

        finish => {
            help     => "request authorization to complete a move job",
            form     => "<userid>:<srcclusterid>:<dstclusterid>",
            args     => qr{^($Tuple)$},
        },

        quit     => {
            help => "disconnect from the server",
            args => qr{^$},
        },

        shutdown => {
            help => "shut the server down",
            args => qr{^$},
        },

        lock     => {
            help => "Pre-lock a given user's job. The job must have already been added.",
            form => '<userid>',
            args => qr{^(\d+)$},
        },

        help     => {
            help => "show list of commands or help for a particular command, if given.",
            form => "[<command>]",
            args => qr{^(\w+)?$},
        },
       );

    # Pattern to match command words
    $CommandPattern = join '|', keys %CommandTable;
    $CommandPattern = qr{^($CommandPattern)$};
}


### (CONSTRUCTOR) METHOD: new( $server=JobServer, $socket=IO::Socket )
### Create a new JobServer::Client object for the given I<socket> and I<server>.
sub new {
    my JobServer::Client $self = shift;
    my $server = shift or confess "no server argument";
    my $sock = shift or confess "no socket argument";

    $self = fields::new( $self ) unless ref $self;
    $self->SUPER::new( $sock );

    $self->{server} = $server;
    $self->{state} = 'new';

    return $self;
}


### METHOD: stringify( undef )
### Return a string representation of the client object.
sub stringify {
    my JobServer::Client $self = shift;

    return sprintf( '%s:%d',
                    $self->{sock}->peerhost,
                    $self->{sock}->peerport );
}


### METHOD: event_read( undef )
### Readable event callback -- read input from the client and append it to the
### read buffer. Then peel lines off the read buffer and send them to the line
### processor.
sub event_read {
    my JobServer::Client $self = shift;

    my $bref = $self->read( 1024 );

    if ( !defined $bref ) {
        $self->close;
        return undef;
    }

    $self->{read_buf} .= $$bref;

    while ($self->{read_buf} =~ s/^(.+?)\r?\n//) {
        $self->processLine( $1 );
    }

}


### METHOD: close( undef )
### Close the client connection after unregistering from the server --
### overridden from Danga::Socket.
sub close {
    my JobServer::Client $self = shift;

    $self->{server}->disconnectClient( $self ) if $self->{server};
    $self->SUPER::close;
}


### METHOD: sock( undef )
### Return the IO::Socket object that corresponds to this client.
sub sock {
    my JobServer::Client $self = shift;
    return $self->{sock};
}


### METHOD: sock( undef )
### Return the file descriptor that is associated with the IO::Socket object
### that corresponds to this client.
sub fdno {
    my JobServer::Client $self = shift;
    return fileno( $self->{sock} );
}


### METHOD: event_err( undef )
### Handle Danga::Socket error events.
sub event_err {
    my JobServer::Client $self = shift;
    $self->close;
}


### METHOD: event_hup( undef )
### Handle Danga::Socket hangup events.
sub event_hup {
    my JobServer::Client $self = shift;
    $self->close;
}


### METHOD: debugMsg( $level, $format, @args )
### Send a debugging message to the server.
sub debugMsg {
    my JobServer::Client $self = shift;
    $self->{server}->debugMsg( @_ );
}


### METHOD: logMsg( $type, $format, @args )
### Send a log message to the server.
sub logMsg {
    my JobServer::Client $self = shift;
    $self->{server}->logMsg( @_ );
}


### METHOD: processLine( $line )
### Command dispatcher -- parse I<line> as a command and dispatch it to the
### correct command handler method. The class-global %CommandTable contains the
### dispatch table for this method.
sub processLine {
    my JobServer::Client $self = shift;
    my $line = shift or return undef;

    my (
        $cmd,                   # Command word
        $args,                  # Argument string
        $argpat,                # Argument-parsing pattern
        @args,                  # Parsed arguments
        $method,                # Command method to call
       );

    # Split the line into command and argument string
    ( $cmd, $args ) = split /\s+/, $line, 2;
    $args = '' if !defined $args;

    $self->debugMsg( 5, "Matching '%s' against command table pattern %s",
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

            eval { $self->$method(@args) };
            if ( $@ ) { $self->errorResponse($@) }
        }

        # Valid command, but bad args
        else {
            $self->errorResponse( "Malformed command args for '$cmd': '$args'." );
        }
    }

    # Invalid command
    else {
        $self->errorResponse( "Invalid or malformed command '$cmd'" );
    }

    return 1;
}


### METHOD: okayResponse( @msg )
### Set an 'OK' response string made up of the I<msg> parts concatenated
### together.
sub okayResponse {
    my JobServer::Client $self = shift;
    my $msg = join( '', @_ );

    1 while chomp( $msg );

    $self->debugMsg( 3, "[Client %s:%d] OK: %s",
                     $self->{sock}->peerhost,
                     $self->{sock}->peerport,
                     $msg,
                    );

    $self->write( "OK $msg\r\n" );
}


### METHOD: errorResponse( @msg )
### Send an 'ERR' response string made up of the I<msg> parts concatenated
### together.
sub errorResponse {
    my JobServer::Client $self = shift;
    my $msg = join( '', @_ );

    # Trim newlines off the end of the message
    1 while chomp( $msg );

    $self->logMsg( "error", "[Client %s:%d] ERR: %s",
                   $self->{sock}->peerhost,
                   $self->{sock}->peerport,
                   $msg,
                  );

    $msg =~ s{at \S+ line \d+\..*}{};
    $self->write( "ERR $msg\r\n" );
}


### METHOD: multilineResponse( $msg, @lines )
### Send an 'OK' response containing the given I<msg> followed by one or more
### I<lines> of a multi-line response followed by an 'END'.
sub multilineResponse {
    my $self = shift or croak "Cannot be used as a function.";
    my ( $msg, @lines ) = @_;

    chomp( @lines );

    $self->okayResponse( $msg );
    $self->write( join("\r\n", @lines, "END") . "\r\n" );
}




#####################################################################
### C O M M A N D   M E T H O D S
#####################################################################

### METHOD: cmd_get_job( undef )
### Command handler for the C<get_job> command.
sub cmd_get_job {
    my JobServer::Client $self = shift;

    $self->{state} = 'getting job';
    my $job = $self->{server}->getJob( $self );

    if ( $job ) {
        $self->{state} = sprintf 'got job %d:%d:%d', @$job;
        return $self->okayResponse( "JOB ". $job->stringify );
    } else {
        $self->{state} = 'idle (no jobs)';
        return $self->okayResponse( "IDLE" );
    }
}


### METHOD: cmd_add_jobs( $argstring )
### Command handler for the C<add_job> command.
sub cmd_add_jobs {
    my JobServer::Client $self = shift;
    my $argstring = shift or return;

    # Turn the argument into an array of arrays
    my @tuples = map {
        JobServer::Job->new( $self, $_ )
    } split /\s*,\s*/, $argstring;

    $self->{state} = sprintf 'adding %d jobs', scalar @tuples;
    my @responses = $self->{server}->addJobs( @tuples );
    $self->{state} = 'idle';

    return $self->multilineResponse( "Done", @responses );
}


### METHOD: cmd_source_counts( undef )
### Command handler for the C<source_counts> command.
sub cmd_source_counts {
    my JobServer::Client $self = shift;
    $self->{state} = 'source counts';
    return $self->errorResponse( "Unimplemented command." );
}

### METHOD: cmd_stop_moves( undef )
### Command handler for the C<stop_moves> command.
sub cmd_stop_moves {
    my JobServer::Client $self = shift;
    my $allFlag = shift || '';

    $self->{state} = 'stop moves';
    my $msg;

    if ( $allFlag ) {
        $msg = $self->{server}->stopAllJobs( $self );
    } else {
        $msg = $self->{server}->stopNewJobs( $self );
    }

    $self->okayResponse( $msg );
}

### METHOD: cmd_is_moving( undef )
### Command handler for the C<is_moving> command.
sub cmd_is_moving {
    my JobServer::Client $self = shift;
    $self->{state} = 'is moving';
    return $self->errorResponse( "Unimplemented command." );
}

### METHOD: cmd_check_instance( undef )
### Command handler for the C<check_instance> command.
sub cmd_check_instance {
    my JobServer::Client $self = shift;
    $self->{state} = 'check instance';
    return $self->errorResponse( "Unimplemented command." );
}

### METHOD: cmd_list_jobs( undef )
### Command handler for the C<list_jobs> command.
sub cmd_list_jobs {
    my JobServer::Client $self = shift;
    $self->{state} = 'list jobs';

    my $stats = $self->{server}->getJobList;

    return $self->multilineResponse(
        "Joblist:",
        "Queued Jobs",
        @{$stats->{queued_jobs}},
        "",
        "Assigned Jobs",
        @{$stats->{assigned_jobs}},
        "",
        @{$stats->{footer}},
       );
}


### METHOD: cmd_set_rate( undef )
### Command handler for the C<set_rate> command.
sub cmd_set_rate {
    my JobServer::Client $self = shift;
    my ( $clusterid, $rate ) = @_;

    my $msg;

    # Global rate
    if ( ! defined $rate ) {
        $rate = $clusterid;
        $self->{state} = "set global rate";
        $msg = $self->{server}->setGlobalRateLimit( $rate );
    }

    else {
        $self->{state} = "set rate for cluster $clusterid";
        $msg = $self->{server}->setClusterRateLimit( $clusterid, $rate );
    }

    return $self->okayResponse( $msg );
}


### METHOD: cmd_finish( undef )
### Command handler for the C<finish> command.
sub cmd_finish {
    my JobServer::Client $self = shift;
    my $spec = shift or confess "No job specification";
    $self->{state} = 'finish';

    my ( $userid, $srcclusterid, $dstclusterid ) = split /:/, $spec, 3;

    my $msg = $self->{server}->requestJobFinish( $self, $userid, $srcclusterid,
                                                 $dstclusterid );

    if ( $msg ) {
        return $self->okayResponse( $msg );
    } else {
        return $self->errorResponse( "Abort" );
    }
}


### METHOD: cmd_help( undef )
### Command handler for the C<help> command.
sub cmd_help {
    my JobServer::Client $self = shift;
    my $command = shift || '';

    $self->{state} = 'help';
    my @response = ();

    # Either show help for a particular command
    if ( $command && exists $CommandTable{$command} ) {
        my $cmdinfo = $CommandTable{ $command };
        $cmdinfo->{form} ||= ''; # Non-existant form means no args

        @response = (
            "--- $command -----------------------------------",
            "",
            "  $command $cmdinfo->{form}",
            "",
            $cmdinfo->{help},
            "",
            "Pattern:",
            "  $cmdinfo->{args}",
            "",
           );
    }

    else {
        my @cmds = map { "  $_" } sort keys %CommandTable;
        @response = (
            "Available commands:",
            "",
            @cmds,
            "",
           );
    }

    return $self->multilineResponse( "Help:", @response );
}


### METHOD: cmd_lock( $userid )
### Command handler for the (debugging) C<lock> command.
sub cmd_lock {
    my JobServer::Client $self = shift;
    my $userid = shift;

    # Fetch the job for the requested user if possible
    my $job = $self->{server}->getJobForUser( $userid )
        or return $self->errorResponse( "No such user '$userid'." );

    if ( $job->isPrelocked ) {
        my $msg = sprintf( "User %d already locked for %d seconds.",
                           $userid, $job->secondsSinceLock );
        return $self->errorResponse( $msg );
    }

    # Try to lock the user
    my $time = $job->prelock;
    if ( $time ) {
        my $msg = "User $userid locked at: $time (". scalar localtime($time) .")";
        return $self->okayResponse( $msg );
    } else {
        return $self->errorResponse( "Prelocking of user $userid failed." );
    }
}


### METHOD: cmd_quit( undef )
### Command handler for the C<quit> command.
sub cmd_quit {
    my JobServer::Client $self = shift;

    $self->{state} = 'quitting';

    $self->okayResponse( "Goodbye" );
    $self->close;

    return 1;
}


### METHOD: cmd_shutdown( undef )
### Command handler for the C<shutdown> command.
sub cmd_shutdown {
    my JobServer::Client $self = shift;

    $self->{state} = 'shutdown';

    my $msg = $self->{server}->shutdown( $self );
    $self->{server} = undef;
    $self->okayResponse( $msg );
    $self->close;

    return 1;
}





# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
