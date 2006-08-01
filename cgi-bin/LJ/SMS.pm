package LJ::SMS;

use strict;
use Carp qw(croak);

use Class::Autouse qw(
                      IO::Socket::INET 
                      XML::Simple
                      LJ::Typemap
                      );

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
#    timecreate: timestamp when message was created
#    type:       'incoming' or 'outgoing' from LJ's perspective
#    body_text:  decoded text body of message
#    body_raw:   raw text body of message
#    meta:       hashref of metadata key/value pairs
#
# synopsis:
#
#    my $sms = LJ::SMS->new($owneru,
#                           from      => $num_or_u,
#                           to        => $num_or_u,
#                           body_text => $utf8_text,
#                           meta      => { k => $v },
#                           );
#
#    my $sms = LJ::SMS->new_from_dsms($owneru, $dsms_msg);
#
# accessors:
#
#    $sms->owner_u;
#    $sms->to_num;
#    $sms->from_num;
#    $sms->to_u;
#    $sms->from_u;
#    $sms->type;
#    $sms->body_text;
#    $sms->raw_text;
#    $sms->timecreate;
#    $sms->meta;
#    $sms->meta($k);

sub schwartz_capabilities {
    return qw(LJ::Worker::IncomingSMS);
}

sub new {
    my ($class, %opts) = @_;
    croak "new is a class method"
        unless $class eq __PACKAGE__;

    my $self = bless {}, $class;

    # from/to can each be passed as either number or $u object
    # in any case $self will end up with the _num and _uid fields
    # specified for each valid from/to arg
    foreach my $k (qw(from to)) {
        my $val = delete $opts{$k};
        next unless $val;

        # extract fields from $u object
        if (LJ::isu($val)) {
            my $u = $val;
            $self->{"${k}_uid"} = $u->{userid};
            $self->{"${k}_num"} = $u->sms_number
                or croak "'$k' user has no mapped number";
            next;
        }

        if ($val =~ /^\d+$/) {
            $self->{"${k}_uid"} = $self->get_uid($val);
            $self->{"${k}_num"} = $val;
            next;
        }

        croak "invalid numeric argument '$k': $val";
    }

    { # owner argument
        my $owner_arg = delete $opts{owner};
        croak "owner argument must be a valid user object"
            unless LJ::isu($owner_arg);

        $self->{owner_uid} = $owner_arg->{userid};
    }

    # type: incoming/outgoing
    $self->{type} = lc(delete $opts{type});
    croak "type must be one of 'incoming' or 'outgoing', from the server's perspective"
        unless $self->{type} =~ /^(?:incoming|outgoing)$/;
    
    # omg we need text eh?
    $self->{body_text} = delete $opts{body_text};
    $self->{body_raw}  = exists $opts{body_raw} ? delete $opts{body_raw} : $self->{body_text};

    { # any metadata the user would like to pass through
        $self->{meta} = delete $opts{meta};
        croak "invalid 'meta' argument"
            if $self->{meta} && ref $self->{meta} ne 'HASH';

        $self->{meta} ||= {};
    }

    # set timecreate stamp for this object
    $self->{timecreate} = time();

    die "invalid argument: " . join(", ", keys %opts)
        if %opts;

    return $self;
}

sub new_from_dsms {
    my ($class, $dsms_msg) = @_;
    croak "new_from_dsms is a class method"
        unless $class eq __PACKAGE__;

    croak "invalid dsms_msg argument: $dsms_msg"
        unless ref $dsms_msg eq 'DSMS::Message';

    my $owneru = undef;
    {
        my $owner_num = $dsms_msg->is_incoming ?
            $dsms_msg->from : $dsms_msg->to;

        $owner_num = $class->normalize_num($owner_num);

        my $uid = $class->get_uid($owner_num)
            or croak "invalid owner id from number: $owner_num";

        $owneru = LJ::load_userid($uid);
        croak "invalid owner u from number: $owner_num"
            unless LJ::isu($owneru);
    }


    # construct a new LJ::SMS 
    my $msg = $class->new
        ( owner     => $owneru,
          from      => $class->normalize_num($dsms_msg->from),
          to        => $class->normalize_num($dsms_msg->to),
          type      => $dsms_msg->type,
          body_text => $dsms_msg->body_text,
          body_raw  => $dsms_msg->body_raw,
          meta      => $dsms_msg->meta, 
          );

    return $msg;
}

# strip full msisdns down to us phone numbers
sub normalize_num {
    my $class = shift;
    my $arg = shift;
    $arg = ref $arg ? $arg->[0] : $arg;

    # FIXME: handle shortcodes
    $arg =~ s/^(?:\+1)(\d{10})$/$1/;
    return $arg;
}

sub meta {
    my $self = shift;
    my $key  = shift;

    my $meta = $self->{meta} || {};
    return $key ? $meta->{$key} : $meta;
}

sub owner_u {
    my $self = shift;

    # load user obj if valid uid and return
    my $uid = $self->{owner_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub to_num {
    my $self = shift;
    return $self->{to_num};
}

sub to_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{to_uid} = $self->get_uid($self->{to_num})
        unless exists $self->{to_uid};

    # load user obj if valid uid and return
    my $uid = $self->{to_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub get_uid {
    my $self = shift;
    my $num  = shift;

    my $dbr = LJ::get_db_reader();
    return $dbr->selectrow_array
        ("SELECT userid FROM smsusermap WHERE number=?", undef, $num);
}

sub from_num {
    my $self = shift;
    return $self->{from_num};
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

sub type {
    my $self = shift;
    return $self->{type};
}

sub timecreate {
    my $self = shift;
    return $self->{timecreate};
}

sub body_text {
    my $self = shift;
    return $self->{body_text};
}

sub body_raw {
    my $self = shift;
    return $self->{body_raw};
}

sub save_to_db {
    my $self = shift;

    my $u = $self->owner_u
        or die "no owner object found";
    my $uid = $u->{userid};

    # allocate a user counter id for this messaGe
    my $msgid = LJ::alloc_user_counter($u, "G")
        or die "Unable to allocate msgid for user: " . $self->owner_u->{user};
    
    # insert main sms_msg row
    $u->do("INSERT INTO sms_msg SET userid=?, msgid=?, type=?, to_number=?, from_number=?, " . 
           "msg_raw=?, timecreate=UNIX_TIMESTAMP()", undef, 
           $uid, $msgid, $self->type, $self->to_num, $self->from_num,
           $self->body_raw);
    die $u->errstr if $u->err;

    my $tm = LJ::Typemap->new
        ( table      => 'sms_msgproplist',
          classfield => 'name',
          idfield    => 'propid',
          );

    my @vals = ();
    while (my ($propname, $propval) = each %{$self->meta}) {
        my $propid = $tm->class_to_typeid($propname);
        push @vals => $uid, $msgid, $propid, $propval;
    }
    my $bind = join(",", map { "(?,?,?,?)" } (1..@vals/4));

    $u->do("INSERT INTO sms_msgprop (userid, msgid, propid, propval) VALUES $bind",
           undef, @vals);
    die $u->errstr if $u->err;

    return 1;
}

# enqueue an incoming SMS for processing
sub enqueue_as_incoming {
    my $class = shift;
    croak "enqueue_as_incoming is a class method"
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

sub send {
    my $self = shift;
    if (my $cv = $LJ::_T_SMS_SEND) {
        return $cv->($self);
    }
    if ($LJ::IS_DEV_SERVER) {
        return $self->send_jabber_dev_server;
    }

    my $gw = LJ::sms_gateway()
        or die "unable to instantiate SMS gateway object";

    my $rv = $gw->send_msg($self);

    # this message has been sent, log it to the db
    # FIXME: this the appropriate time?
    $self->save_to_db;

    return 1;
}

sub send_jabber_dev_server {
    my $self = shift;

    my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5224")
        or return 0;

    print $sock "set_vhost $LJ::DOMAIN\n";
    my $okay = <$sock>;
    return 0 unless $okay =~ /^OK/;

    my $to = $self->to_num . '@' . $LJ::DOMAIN;
    my $msg = $self->body_text;
    my $xml = qq{<message type='chat' to='$to' from='sms\@$LJ::DOMAIN'><x xmlns='jabber:x:event'><composing/></x><body>$msg</body><html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'><html>$msg</html></body></html></message>};
    print $sock ("send_xml $to " . LJ::eurl($xml) . "\n");
    return 1;
}

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{body_text}\n";
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

    # save msg to the db
    $msg->save_to_db
        or die "unable to save message to db";

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
