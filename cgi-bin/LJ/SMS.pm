package LJ::SMS;

use strict;
use Carp qw(croak);

use Class::Autouse qw(IO::Socket::INET XML::Simple);

# LJ::SMS object
#
# internal fields:
#
#    owner_uid:  userid of the 'owner' of this SMS
#                -- the user object who is sending
#                   or receiving this message
#    from_uid:   userid of the sender
#    from_num:   phone number of sender
#    to_uid:     userid of the recipient
#    to_num:     phone number of recipient
#    text:       text body of message
#    meta:       hashref of metadata key/value pairs
#
# synopsis:
#
#    my $sms = LJ::SMS->new($u,
#                           from => $num_or_u,
#                           to   => $num_or_u,
#                           text => $utf8_text,
#                           meta => { k => $v },
#                           );
#
# accessors:
#
#    $sms->owner_u;
#    $sms->to_num;
#    $sms->from_num;
#    $sms->to_u;
#    $sms->from_u;
#    $sms->text;
#    $sms->meta;
#    $sms->meta($k);

sub schwartz_capabilities {
    return qw(LJ::Worker::IncomingSMS);
}

sub new {
    my ($class, %opts) = @_;
    die "new is a class method"
        unless $class eq __PACKAGE__;


    my $self = bless {}, $class;

    # from/to can each be passed as either number or $u object
    # in any case $self will end up with the _num and _uid fields
    # specified for each valid from/to arg
    foreach my $k (qw(from to)) {
        my $val = delete $opts{$k};
        next unless $opts{$k};

        # extract fields from $u object
        if (LJ::isu($val)) {
            my $u = $val;
            $self->{"${k}_uid"} = $u->{userid};
            $self->{"${k}_num"} = $u->sms_number
                or croak "'$k' user has no mapped number";
        } elsif ($val !~ /^\d+$/) {
            croak "invalid numeric argument '$k': $val";
            $self->{"${k}_uid"} = $self->get_uid($val);
            $self->{"${k}_num"} = $val;
        }
    }

    # omg we need text eh?
    $self->{text} = delete $opts{text};

    { # any metadata the user would like to pass through
        $self->{meta} = delete $opts{meta};
        croak "invalid 'meta' argument"
            if $self->{meta} && ref $self->{meta} ne 'HASH';

        $self->{meta} ||= {};
    }

    # save this message to the db
    #$self->save_to_db;

    die "foo" if %opts;
    return $self;
}

sub new_from_dsms {
    my ($class, $dsms_msg) = @_;
    die "new_from_dsms is a class method"
        unless $class eq __PACKAGE__;

    die "invalid dsms_msg argument: $dsms_msg"
        unless ref $dsms_msg eq 'DSMS::Message';

    # strip full msisdns down to us phone numbers
    my $normalize = sub {
        my $arg = shift;
        $arg = ref $arg ? $arg->[0] : $arg;

        # FIXME: handle shortcodes
        $arg =~ s/^(?:\+1)(\d{10})$/$1/;
        return $arg;
    };

    # construct a new LJ::SMS 
    my $msg = $class->new
        ( from => $normalize->($dsms_msg->from),
          to   => $normalize->($dsms_msg->to),
          text => $dsms_msg->body_text,
          meta => $dsms_msg->meta,
          );
}

sub meta {
    my $self = shift;
    my $key  = shift;

    my $meta = $self->{meta};
    return $key ? $meta->{$key} : $meta;
}

sub to {
    my $self = shift;
    return $self->{to};
}

sub to_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{_to_uid} = $self->get_uid($self->{to})
        unless exists $self->{_to_uid};

    # load user obj if valid uid and return
    my $uid = $self->{_to_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub get_uid {
    my $self = shift;
    my $num  = shift;

    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array
        ("SELECT userid FROM smsusermap WHERE number=?", undef, $num);
}

sub from {
    my $self = shift;
    return $self->{from};
}

sub from_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{_to_uid} = $self->get_uid($self->{to})
        unless exists $self->{_to_uid};

    # load user obj if valid uid and return
    my $uid = $self->{_to_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub text {
    my $self = shift;
    return $self->{text};
}

sub log_to_db {
    my $self = shift;

    
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

sub should_enqueue { 1 }

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
