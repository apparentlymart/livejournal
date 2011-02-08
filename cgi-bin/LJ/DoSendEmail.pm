package LJ::DoSendEmail;
use Net::DNS qw(mx);
use LJ::User::Email;

## Class prop
my $resolver;
my $status  = '';
my $code    = '';
my $error   = '';
my $details = '';

## Class accessors
sub error {
    my $class = shift;
    $error = $_[0] if @_ > 0;
    return $error;
}

sub status {
    my $class = shift;
    $status = $_[0] if @_ > 0;
    return $status;
}

sub code {
    my $class = shift;
    $code = $_[0] if @_ > 0;
    return $code;
}


sub details {
    my $class = shift;
    $details = $_[0] if @_ > 0;
    return $details;
}

##
## Send function
##
# status_code:
#   undef   - OK
#   0       - cannot connect to MX-host or email domain.
#   5xx     - smtp-status
#
#sub log_complete_status {
#    my $status_code = shift;
#    my $emails      = shift;    # One email if scalar or list of emails if array ref.
#    my $message     = shift;
#
#    LJ::User::Email->mark($status_code, $emails, $message);
#}

sub set_resolver { $resolver = $_[1] }
sub resolver { $resolver ||= Net::DNS::Resolver->new() }


use constant OK => 0;
use constant NO_RCPT => 1;
use constant NO_SUPPORTED_RCPT => 2;
use constant CONNECTION_FAILED => 3;
use constant SMTP_ERROR_NO_RCPT_ON_SERVER => 4;
use constant SMTP_ERROR_PERMANENT         => 5;
use constant SMTP_ERROR_GENERAL           => 6;

##
## ->send(
##      $rcpt,
##      {
##          from         = From
##          data         = raw email with headers and bod
##          timeout      = Maximum time, in seconds, to wait for a response from the SMTP server (perldoc Net::SMTP). Default: 300
##          sender_id    = ...
##          hello_domain = ... (optional)
##      }
## )
## 
## Returns one of constants defined above.
sub send {
    my $class = shift;
    my ($rcpt, $opts) = @_;

    ## read params
    my $from         = $opts->{from}; # Envelope From
    my $data         = $opts->{data};
    my $timeout      = $opts->{timeout} || 300;
    my $hello_domain = $opts->{hello_domain} || $LJ::DOMAIN;

    ## flush class properties
    $class->status('');
    $class->code('');
    $class->error('');
    $class->details('');

    ## is there other side? ))
    return NO_RCPT unless $rcpt;

    my ($host) = $rcpt =~ /\@(.+?)$/;
    return NO_SUPPORTED_RCPT unless $host;

    my @ex = ();
    if ($LJ::IS_DEV_SERVER){
        @ex = ('127.0.0.1'); ## use local relay
        @ex = ('172.19.1.1');
    } else {
        ## give me the numbers!
        my @mailhosts = mx(resolver(), $host);
        @ex = map { $_->exchange } @mailhosts;
    }

    # seen in wild:  no MX records, but port 25 of domain is an SMTP server.  think it's in SMTP spec too?
    @ex = ($host) unless @ex;

    my $smtp = Net::SMTP::BetterConnecting->new(
                                                \@ex,
                                                Hello          => $hello_domain,
                                                PeerPort       => 25,
                                                ConnectTimeout => 4,
                                                );
    unless ($smtp) {
        $class->error("Connection failed to domain '$host', MXes: [@ex]");
        LJ::User::Email->mark(0, $rcpt, $class->error);
        return CONNECTION_FAILED;
    }

    ## Maximum time, in seconds, to wait for a response from the SMTP server
    $smtp->timeout($timeout);
    # FIXME: need to detect timeouts to log to errors, so people with ridiculous timeouts can see that's why we're not delivering mail

    my ($this_domain) = $from =~ /\@(.+)/;

    # remove bcc
    my $body = $data;
       $body =~ s/^(.+?\r?\n\r?\n)//s;
    my $headers = $1;
       $headers =~ s/^bcc:.+\r?\n//mig; ## remove

    ## sender_id should provide as much info for debug as possible.
    ## For emails that send TheSchwartz worker is may be a 
    ##      $job->handle->as_string.
    ##
    ## Also $sender_id is used as mail id.
    my $sender_id = $opts->{sender_id};
    unless ($sender_id){
        ## generate it.
        require Sys::Hostname;
        $sender_id = Sys::Hostname::hostname();
        $sender_id =~ s/[^-]+//;
        
        $sender_id .= "-" . $$ . "-" . time();
    }

    # unless they specified a message ID, let's prepend our own:
    unless ($headers =~ m!^message-id:.+!mi) {
        my $rand = LJ::rand_chars(8);
        my $message_id = qq|<sch-$sender_id-$rand\@$this_domain>|;
        $headers = "Message-ID: $message_id\r\n" . $headers;
    }

    ## _do_send returns nothing on success or failed command on error.
    my $res = $class->_do_send($smtp, $from, $rcpt, $sender_id, 
                               $headers, $body);
    $class->status($smtp->status);
    eval { $class->code( $smtp->code ) };
    my $details = eval { $smtp->code . " " . $smtp->message };
    $smtp->quit; ##

    if ($res){ ## ERROR
        ## handle 5xx errors
        # ...
        # #? $class->on_5xx_rcpt($job, $rcpt, $details->());

        $class->error("Permanent failure during $failed_phase phase to [$rcpt]: $details \n");

        ## log error
        LJ::User::Email->mark(5, $rcpts, $err_msg);

        ## handle other errors
        if ($failed_phase eq "TO"){
        ## Permanent error
        ## no need to retry attempts
            return SMTP_ERROR_NO_RCPT_ON_SERVER;
        }

        if ($class->status == 5){
            return SMTP_ERROR_PERMANENT;
        }

        return SMTP_ERROR_GENERAL;
    }


    ## flush errors if they are.
    LJ::User::Email->mark(undef, $rcpt, "OK");

    ##
    return OK;
}

## Send SMTP commands to server.
##      On success returns nothing
##      On error returns a command that failed.
sub _do_send {
    my $class = shift;
    my ($smtp, $env_from, $rcpt, $mail_id, $headers, $body) = @_;

    ## Send command MAIL to server.
    my $res = $smtp->mail($env_from);

    ## In case of error return name of command that failed.
    return "MAIL" unless $res;

    ## Provide recipient to server 
    $res = $smtp->to($rcpt);
    return "TO" unless $res; # return error

    # have to add a fake "Received: " line in here, otherwise some
    # stupid over-strict MTAs like bellsouth.net reject it thinking
    # it's spam that was sent directly (it was).  Called
    # "NoHopsNoAuth".
    $mail_id =~ s/-/00/;  # not sure if hyphen is allowed in
    my $date = _rfc2822_date(time());
    my $rcvd = qq{Received: from localhost (theschwartz [127.0.0.1])
                      by $this_domain (TheSchwartzMTA) with ESMTP id $mail_id;
                      $date
                  };
    $rcvd =~ s/\s+$//;
    $rcvd =~ s/\n\s+/\r\n\t/g;
    $rcvd .= "\r\n";

    ## Send commands to server. On error returns the stage name.
    return "DATA"     unless $smtp->data;
    return "DATASEND" unless $smtp->datasend($rcvd . $headers . $body);
    return "DATAEND"  unless $smtp->dataend;

    return; # OK
}


sub _rfc2822_date {
    my $time = shift;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) =
        gmtime($time);
    my @days = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
    my @mon  = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    return sprintf("%s, %d %s %4d %02d:%02d:%02d +0000 (UTC)",
                   $days[$wday], $mday, $mon[$mon], $year+1900, $hour, $min, $sec);
}

package Net::SMTP::BetterConnecting;
use strict;
use base 'Net::SMTP';
use Net::Config;
use Net::Cmd;

# Net::SMTP's constructor could use improvement, so this is it:
#     -- retry hosts, even if they connect and say "4xx service too busy", etc.
#     -- let you specify different connect timeout vs. command timeout
sub new {
    my $self = shift;
    my $type = ref($self) || $self;
    my ($host, %arg);
    if (@_ % 2) {
        $host = shift;
        %arg  = @_;
    } else {
        %arg  = @_;
        $host = delete $arg{Host};
    }

    my $hosts = defined $host ? $host : $NetConfig{smtp_hosts};
    my $obj;
    my $timeout         = $arg{Timeout} || 120;
    my $connect_timeout = $arg{ConnectTimeout} || $timeout;

    my $h;
    foreach $h (@{ref($hosts) ? $hosts : [ $hosts ]}) {
        $obj = $type->IO::Socket::INET::new(PeerAddr => ($host = $h),
                                            PeerPort => $arg{Port} || 'smtp(25)',
                                            LocalAddr => $arg{LocalAddr},
                                            LocalPort => $arg{LocalPort},
                                            Proto    => 'tcp',
                                            Timeout  => $connect_timeout,
                                            )
            or next;

        $obj->timeout($timeout);  # restore the original timeout
        $obj->autoflush(1);
        $obj->debug(exists $arg{Debug} ? $arg{Debug} : undef);

        my $res = $obj->response();
        unless ($res == CMD_OK) {
            $obj->close();
            $obj = undef;
            next;
        }

        last if $obj;
    }

    return undef unless $obj;

    ${*$obj}{'net_smtp_exact_addr'} = $arg{ExactAddresses};
    ${*$obj}{'net_smtp_host'}       = $host;
    (${*$obj}{'net_smtp_banner'})   = $obj->message;
    (${*$obj}{'net_smtp_domain'})   = $obj->message =~ /\A\s*(\S+)/;

    unless ($obj->hello($arg{Hello} || "")) {
        $obj->close();
        return undef;
    }

    return $obj;
}

1;
