package LJ::SMS;

use strict;
use Carp qw(croak);

use Class::Autouse qw(IO::Socket::INET XML::Simple);

sub schwartz_capabilities {
    return qw(LJ::Worker::IncomingSMS);
}

sub new {
    my ($class, %opts) = @_;
    die "new is a class method"
        unless $class eq __PACKAGE__;


    my $self = bless {}, $class;

    # smsusermap, pass in from/to as u/number
    foreach my $k (qw(from to)) {
        $self->{$k} = delete $opts{$k};
        if (LJ::isu($self->{$k})) {
            my $u = $self->{$k};
            $self->{$k} = $u->sms_number
                or croak("'$k' user has no mapped number");
        } elsif ($self->{$k} !~ /^\d+$/) {
            croak ("invalid numeric argument '$k': $self->{$k}");
        }
    }
    $self->{text} = delete $opts{text};
    die if %opts;
    return $self;
}

sub new_from_dsms {
    my ($class, $dsms_msg) = @_;
    die "new_from_dsms is a class method"
        unless $class eq __PACKAGE__;

    die "invalid dsms_msg argument: $dsms_msg"
        unless ref $dsms_msg eq 'DSMS::Message';

    my $normalize = sub {
        my $arg = shift;
        $arg = ref $arg ? $arg->[0] : $arg;
        $arg =~ s/^(?:\+1)(\d{10})$/$1/;
        return $arg;
    };

    return $class->new
        ( from => $normalize->($dsms_msg->from),
          to   => $normalize->($dsms_msg->to),
          # FIXME: subject?
          text => $dsms_msg->body_text,
          );         
}

sub to {
    return $_[0]{to};
}

sub to_u {
    my $self = shift;
    my $tonum = $self->{to};
    my $dbr = LJ::get_db_reader();
    my $uid = $dbr->selectrow_array("SELECT userid FROM smsusermap WHERE number=?",
                                    undef, $tonum);
    return $uid ? LJ::load_userid($uid) : undef;
}

sub from {
    return $_[0]{from};
}

# FIXME: combine this with to_u
sub from_u {
    my $self = shift;
    my $fromnum = $self->{from};
    my $dbr = LJ::get_db_reader();
    my $uid = $dbr->selectrow_array("SELECT userid FROM smsusermap WHERE number=?",
                                    undef, $fromnum);
    return $uid ? LJ::load_userid($uid) : undef;
}


sub text {
    return $_[0]{text};
}

sub owner { # FIXME: change to 'sender_u' or something
    my $self = shift;
    my $from = shift || $self->{from}
        or return undef;

    my $dbr = LJ::get_db_reader();
    my $uid = $dbr->selectrow_array("SELECT userid FROM smsusermap WHERE number=?",
                                    undef, $from);
    return $uid ? LJ::load_userid($uid) : undef;
}

sub set_to {
    my ($self, $to) = @_;
    $self->{to} = $to;
}

# enqueue an incoming SMS for processing
sub enqueue_as_incoming {
    my $class = shift;
    die "enqueue_as_incoming is a class method"
        unless $class eq __PACKAGE__;

    my $msg = shift;
    die "invalid msg argument"
        unless ref $msg;

    return unless $msg->should_enqueue;

    my $sclient = LJ::theschwartz();
    die "Unable to contact TheSchwartz!"
        unless $sclient;

    my $shandle = $sclient->insert("LJ::Worker::IncomingSMS", $msg);
    warn "insert: $shandle";
    return $shandle ? 1 : 0;
}

sub should_enqueue {
    my $self = shift;

    return 1;
}

# process an incoming SMS
sub worker_process_incoming {
    my $self = shift;


}

sub send {
    my $self = shift;
    if (my $cv = $LJ::_T_SMS_SEND) {
        return $cv->($self);
    }
    if ($LJ::IS_DEV_SERVER) {
        return $self->send_jabber_dev_server;
    }

    warn "LJ::SMS->send() not implemented yet";
}

sub send_jabber_dev_server {
    my $self = shift;

    my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5224")
        or return 0;

    print $sock "set_vhost $LJ::DOMAIN\n";
    my $okay = <$sock>;
    return 0 unless $okay =~ /^OK/;

    my $to = $self->{to} . '@' . $LJ::DOMAIN;
    my $msg = $self->{text};
    my $xml = qq{<message type='chat' to='$to' from='sms\@$LJ::DOMAIN'><x xmlns='jabber:x:event'><composing/></x><body>$msg</body><html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'><html>$msg</html></body></html></message>};
    print $sock ("send_xml $to " . LJ::eurl($xml) . "\n");
    return 1;
}

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{text}\n";
}

# is sms sending configured?
sub configured {
    my $class = shift;

    return %LJ::SMS_GATEWAY_CONFIG && LJ::sms_gateway() ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    # FIXME: for now just check to see if the user has
    #        a uid -> number mapping in smsusermap
    return $class->number($u) ? 1 : 0;
}

# Schwartz worker for responding to incoming SMS messages
package LJ::Worker::IncomingSMS;

use base 'TheSchwartz::Worker';

sub work {
    my ($class, $job) = @_;

    my $msg = $job->arg;

    unless ($msg) {
        $job->failed;
        return;
    }

    use Data::Dumper;
    print "msg: " . Dumper($msg);

    # message command handler code
    {
        my $u = $msg->from_u;
        print "u: $u ($u->{user})\n";

        # build a post event request.
        my $req = {
            usejournal  => undef, 
            ver         => 1,
            username    => $u->{user},
            lineendings => 'unix',
            subject     => "SMS Post",
            event       => ("test body " . time()),
            props       => {},
            security    => 'public',
            tz          => 'guess',
        };

        my $err;
        my $res = LJ::Protocol::do_request("postevent",
                                           $req, \$err, { 'noauth' => 1 });

        if ($err) {
            my $errstr = LJ::Protocol::error_message($err);
            print "ERROR: $errstr\n";
        }

        print "res: $res\n";
    }
    
    return $job->completed;
}

sub keep_exit_status_for { 0 }
sub grab_for { 300 }
sub max_retries { 5 }
sub retry_delay {
    my ($class, $fails) = @_;
    return (10, 30, 60, 300, 600)[$fails];
}

1;
