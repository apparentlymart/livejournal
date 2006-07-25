#!/usr/bin/perl
#
# Send mail outbound using a weighted random selection.
# Supports a variety of mail protocols.
#

package LJ;

use strict;
use Text::Wrap ();
use MIME::Lite ();
use Time::HiRes qw/ gettimeofday tv_interval /;

use IO::Socket::INET (); # temp, for use with DMTP

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

sub maildebug     ($);
sub store_message (%$$);

# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.  Character set will only be used if message is not ascii.
# args: opt[, async_caller]
# des-opt: Hashref of arguments.  <b>Required:</b> to, from, subject, body.
#          <b>Optional:</b> toname, fromname, cc, bcc, charset, wrap
# </LJFUNC>
sub send_mail
{
    my $opts         = shift;
    my $async_caller = shift;
    my $time = [gettimeofday()];

    my (
        $proto,    # what protocol we decided to use
        $msg,      # email message (ascii)
        $data,     # email message (MIME::Lite)
        $server,   # remote server object
        $hostname  # hostname of mailserver selected
    );

    # support being given a direct MIME::Lite object,
    # for queued cmdbuffer 'frozen' retries
    $data = ( ref $opts eq 'MIME::Lite' ) ? $opts : build_message($opts);
    return 0 unless $data;
    $msg = $data->as_string();

    # ok, we're sending via the network.
    # get a preferred server/protocol, or failover to cmdbuffer.
    ( $server, $proto, $hostname ) = find_server();
    unless ( $server && $proto ) {
        maildebug "Suitable mail transport not found.";
        return store_message $data, undef;
    }
    my $info = "$hostname-$proto";

    # Now we have an active server connection,
    # and we know what protocol to use.

    # clean addresses.
    my ( @recips, %headers );
    $headers{$_} = $data->get( $_ ) foreach qw/ from to cc bcc /;

    $opts->{'from'} =
        ( Mail::Address->parse( $data->get('from') ) )[0]->address()
            if $headers{'from'};

    push @recips, map { $_->address() } Mail::Address->parse( $headers{'to'} )  if $headers{'to'};
    push @recips, map { $_->address() } Mail::Address->parse( $headers{'cc'} )  if $headers{'cc'};
    push @recips, map { $_->address() } Mail::Address->parse( $headers{'bcc'} ) if $headers{'bcc'};

    unless (scalar @recips) {
        maildebug "No recipients to send to!";
        return 0;
    }

    # QMTP
    if ( $proto eq 'qmtp' ) {
        $server->recipient($_) foreach @recips;
        $server->sender( $opts->{'from'} );
        $server->message($msg);

        # send!
        my $response = $server->send() or return store_message $data, $info;
        foreach ( keys %$response ) {
            return store_message $data, $info
              if $response->{$_} !~ /success/;
        }
        $server->disconnect();
    }

    # SMTP
    if ( $proto eq 'smtp' ) {

        $server->mail( $opts->{'from'} );

        # this would only fail on denied relay access
        # or somesuch.
        return store_message $data, $info unless
            $server->to( join ', ', @recips );

        $server->data();
        $server->datasend($msg);
        $server->dataend();

        $server->quit;
    }

    # DMTP (Danga Mail Transfer Protocol)
    # (slated for removal if our QMTP stuff is worry-free.)
    if ( $proto eq 'dmtp' ) {

        my $len = length $msg;
        my $env = $opts->{'from'};

        $server->print("Content-Length: $len\r\n");
        $server->print("Envelope-Sender: $env\r\n\r\n$msg");

        return store_message $data, $info
            unless $server->getline() =~ /^OK/;
    }

    # system mailer
    if ( $proto eq 'sendmail' ) {
        MIME::Lite->send( 'sendmail', $hostname );
        unless ( $data->send() ) {
            maildebug "Unable to send via system mailer!";
            return store_message $data, 'sendmail';
        }
    }

    report( $data, $time, $info, $async_caller );
    return 1;
}

sub report
{
    my ( $data, $time, $info, $async_caller ) = @_;

    # report deliveries
    my $notes = sprintf(
        "Direct mail send to %s succeeded: %s",
        $data->get('to') ||
        $data->get('cc') ||
        $data->get('bcc'), $data->get('subject')
    );
    maildebug $notes;

    LJ::blocking_report(
        $info, 'send_mail',
        tv_interval( $time ), $notes
      )
      unless $async_caller;

    return;
}

# locate a network server,
# return (serverobj, protocol, hostname)
sub find_server
{
    # operate on a copy of the server list.
    my @objects = @LJ::MAIL_TRANSPORTS;

    # backwards compatibility with earlier ljconfig.
    unless (@objects) {
        push @objects, [ 'sendmail', $LJ::SENDMAIL,    0 ] if $LJ::SENDMAIL;
        push @objects, [ 'smtp',     $LJ::SMTP_SERVER, 0 ] if $LJ::SMTP_SERVER;
        push @objects, [ 'dmtp',     $LJ::DMTP_SERVER, 1 ] if $LJ::DMTP_SERVER;
    }

    my ( $server, $proto, $hostname );

    while ( @objects && !$proto ) {
        my $item   = get_slice(@objects);
        my $select = $objects[$item];

        maildebug "Trying server $select->[1] ($select->[0])...";

        # check service connectivity

        # QMTP
        if ( $select->[0] eq 'qmtp' ) {
            eval 'use Net::QMTP';
            if ($@) {
                maildebug "Net::QMTP not installed?";
                splice @objects, $item, 1;
                next;
            }

            eval {
                $server = Net::QMTP->new( $select->[1], ConnectTimeout => 10 );
            };
        }

        # SMTP
        elsif ( $select->[0] eq 'smtp' ) {
            eval 'use Net::SMTP';
            if ($@) {
                maildebug "Net::SMTP not installed?";
                splice @objects, $item, 1;
                next;
            }

            eval { $server = Net::SMTP->new( $select->[1], Timeout => 10 ); };
        }

        # DMTP
        elsif ( $select->[0] eq 'dmtp' ) {
            my $host = $select->[1];
            my $port = $host =~ s/:(\d+)$// ? $1 : 7005;

            $server = IO::Socket::INET->new(
                PeerAddr => $host,
                PeerPort => $port,
                Proto    => 'tcp'
            );
        }

        # system sendmail binary
        elsif ( $select->[0] eq 'sendmail' ) {
            my $sendmail = $1 if $select->[1] =~ /(\S+)/;
            $server = $sendmail if -e $sendmail && -x _;
        }

        else {
            maildebug "Unknown mail protocol";
            splice @objects, $item, 1;
            next;
        }

        # do we have a server connection?
        # if not, remove from our selection pool and try again.
        if ( ! $server ) {
            maildebug "Could not connect";
            splice @objects, $item, 1;
        }
        else {
            maildebug "Connected";
            ( $proto, $hostname ) = ( $select->[0], $select->[1] );
        }
    }

    return ( $server, $proto, $hostname );
}

# return a ready to stringify MIME::Lite object.
sub build_message
{
    my $opts = shift;

    my $body = $opts->{'wrap'} ?
               Text::Wrap::wrap( '', '', $opts->{'body'} ) :
               $opts->{'body'};

    my $to   = Mail::Address->new( $opts->{'toname'},   $opts->{'to'} );
    my $from = Mail::Address->new( $opts->{'fromname'}, $opts->{'from'} );

    my $msg = MIME::Lite->new
        (
         To      => $to->format(),
         From    => $from->format(),
         Cc      => $opts->{'cc'}  || '',
         Bcc     => $opts->{'bcc'} || '',
         Subject => $opts->{'subject'},
         Type    => 'multipart/alternative',
        );
    return unless $msg;

    $msg->add(%{ $opts->{'headers'} }) if ref $opts->{'headers'};

    $msg->attr("content-type.charset" => $opts->{'charset'})
        if $opts->{'charset'} &&
           ! (LJ::is_ascii($opts->{'body'}) &&
              LJ::is_ascii($opts->{'subject'}));


    # add the plaintext version
    $msg->attach(
                 'Type'     => 'TEXT',
                 'Data'     => "$body\n",
                 'Encoding' => 'quoted-printable',
                 );

    # add the html version
    $msg->attach(
                 'Type'     => 'text/html',
                 'Data'     => $opts->{html},
                 'Encoding' => 'quoted-printable',
                 ) if $opts->{html};

    return $msg;
}

# return a weighted random slice from an array.
sub get_slice
{
    my @objects = @_;

    # Find cumulative values between weights, and in total.
    my (@csums, $cumulative_sum);
    @csums = map { $cumulative_sum += abs $_->[2] } @objects;

    # *nothing* has weight? (all zeros?) just choose one.
    # same thing as equal weights.
    return int rand scalar @objects unless $cumulative_sum;

    # Get a random number that will be compared to
    # the 'window' of probability for quotes.
    my $rand = rand $cumulative_sum;

    # Create number ranges between each cumulative value,
    # and check the random number to see if it falls within
    # the weighted 'window size'.
    # Remember the array slice for matching the original object to.
    my $lastval = 0;
    my $slice   = 0;
    foreach (@csums) {
        last if $rand >= $lastval && $rand <= $_;
        $slice++;
        $lastval = $_;
    }

    return $slice;
}

sub store_message (%$$)
{
    my ( $data, $type ) = @_;
    $type ||= 'none';

    maildebug "Storing message for retry.";
    my $time = [ gettimeofday() ];

    # try this on each cluster
    my $frozen = Storable::freeze($data);
    my $rval   = LJ::do_to_cluster(
        sub {
            # first parameter is cluster id
            return LJ::cmd_buffer_add( shift(@_), 0, 'send_mail', $frozen );
        }
    );
    return undef unless $rval;

    my $notes = sprintf(
        "Queued mail send to %s %s: %s",
        $data->get('to'), $rval ? "succeeded" : "failed",
        $data->get('subject')
    );
    maildebug $notes;

    LJ::blocking_report(
        $type, 'send_mail',
        tv_interval($time), $notes
    );

    # we only attempt to store the message
    # on delivery failure.  if we're here, something
    # failed, so always return false.
    return 0;
}

sub maildebug ($)
{
    return unless $LJ::DEBUG{'email_outgoing'};
    print STDERR "ljmail: " . shift() . "\n";
}


1;

