package LJ::SMS::Message;

use strict;
use Carp qw(croak);

use Class::Autouse qw(
                      IO::Socket::INET
                      LJ::Typemap
                      DSMS::Message
                      );

# LJ::SMS::Message object
#
# internal fields:
#
# FIXME: optional msgid arg if in db?
#
#    owner_uid:  userid of the 'owner' of this SMS
#                -- the user object who is sending
#                   or receiving this message
#    from_uid:   userid of the sender
#    from_num:   phone number of sender
#    to_uid:     userid of the recipient
#    to_num:     phone number of recipient
#    msgid:      optional message id if saved to DB
#    timecreate: timestamp when message was created
#    type:       'incoming' or 'outgoing' from LJ's perspective
#    status:     'success', 'error', or 'unknown' depending on msg status
#    error:      error string associated with this message, if any
#    body_text:  decoded text body of message
#    body_raw:   raw text body of message
#    meta:       hashref of metadata key/value pairs
#
# synopsis:
#
#    my $sms = LJ::SMS->new(owner     => $owneru,
#                           type      => 'outgoing',
#                           status    => 'unknown',
#                           from      => $num_or_u,
#                           to        => $num_or_u,
#                           body_text => $utf8_text,
#                           meta      => { k => $v },
#                           );
#
#    my $sms = LJ::SMS->new_from_dsms($dsms_msg);
#
# accessors:
#
#    $sms->owner_u;
#    $sms->to_num;
#    $sms->from_num;
#    $sms->to_u;
#    $sms->from_u;
#    $sms->type;
#    $sms->status;
#    $sms->error;
#    $sms->msgid;
#    $sms->body_text;
#    $sms->raw_text;
#    $sms->timecreate;
#    $sms->meta;
#    $sms->meta($k);

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

        # normalize the number before validating...
        $val = $self->normalize_num($val);

        if ($val =~ /^\+?\d+$/) {
            $self->{"${k}_uid"} = LJ::SMS->num_to_uid($val);
            $self->{"${k}_num"} = $val;
            next;
        }

        croak "invalid numeric argument '$k': $val";
    }

    # type: incoming/outgoing.  attempt to infer if none is specified
    $self->{type} = lc(delete $opts{type});
    unless ($self->{type}) {
        if ($self->{from_uid} && $self->{to_uid}) {
            croak "cannot send user-to-user messages";
        } elsif ($self->{from_uid}) {
            $self->{type} = 'incoming';
        } elsif ($self->{to_uid}) {
            $self->{type} = 'outgoing';
        }
    }

    # now validate an explict or inferred type
    croak "type must be one of 'incoming' or 'outgoing', from the server's perspective"
        unless $self->{type} =~ /^(?:incoming|outgoing)$/;

    # from there, fill in the from/to num defaulted to $LJ::SMS_SHORTCODE
    if ($self->{type} eq 'outgoing') {
        croak "need valid 'to' argument to construct outgoing message"
            unless $self->{"to_num"};
        $self->{from_num} ||= $LJ::SMS_SHORTCODE;
    } else {
        croak "need valid 'from' argument to construct incoming message"
            unless $self->{"from_num"};
        $self->{to_num} ||= $LJ::SMS_SHORTCODE;
    }

    { # owner argument
        my $owner_arg = delete $opts{owner};
        croak "owner argument must be a valid user object"
            unless LJ::isu($owner_arg);

        $self->{owner_uid} = $owner_arg->{userid};
    }

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
    $self->{timecreate} = delete $opts{timecreate} || time();
    croak "invalid 'timecreate' parameter: $self->{timecreate}"
        unless int($self->{timecreate}) > 0;

    # by default set status to 'unknown'
    $self->{status} = lc(delete $opts{status}) || 'unknown';
    croak "invalid msg status: $self->{status}"
        unless $self->{status} =~ /^(?:success|error|unknown)$/;
    
    # set msgid if a non-zero one was specified
    $self->{msgid} = delete $opts{msgid};
    croak "invalid msgid: $self->{msgid}"
        if $self->{msgid} && int($self->{msgid}) <= 0;

    # probably no error string specified here
    $self->{error} = delete $opts{error} || undef;

    die "invalid argument: " . join(", ", keys %opts)
        if %opts;

    return $self;
}

sub load {
    my $class = shift;
    croak "load is a class method"
        unless $class eq __PACKAGE__;

    my ($owner_u, $msgid) = @_;
    croak "invalid owner_u: $owner_u" 
        unless LJ::isu($owner_u);
    croak "invalid msgid: $msgid"
        unless $msgid && int($msgid) > 0;

    my $uid = $owner_u->{userid};

    my $msg_row = $owner_u->selectrow_hashref
        ("SELECT type, status, to_number, from_number, timecreate " . 
         "FROM sms_msg WHERE userid=? AND msgid=?", undef, $uid, $msgid);
    die $owner_u->errstr if $owner_u->err;

    my $text_row = $owner_u->selectrow_hashref
        ("SELECT msg_raw, msg_decoded FROM sms_msgtext WHERE userid=? AND msgid=?",
         undef, $uid, $msgid);
    die $owner_u->errstr if $owner_u->err;

    my $error = $owner_u->selectrow_array
        ("SELECT error FROM sms_msgerror WHERE userid=? AND msgid=?",
         undef, $uid, $msgid);
    die $owner_u->errstr if $owner_u->err;

    # BARF: need this centralized
    my $tm = $class->typemap;

    my %props = ();
    my $sth = $owner_u->prepare
        ("SELECT propid, propval FROM sms_msgprop WHERE userid=? AND msgid=?");
    $sth->execute($uid, $msgid);
    while (my ($propid, $propval) = $sth->fetchrow_array) {
        my $propname = $tm->typeid_to_class($propid)
            or die "no propname for propid: $propid";

        $props{$propname} = $propval;
    }

    my $msg = $class->new
        ( owner      => $owner_u,
          msgid      => $msgid,
          from       => $msg_row->{from_number},
          to         => $msg_row->{to_number},
          type       => $msg_row->{type},
          status     => $msg_row->{status},
          timecreate => $msg_row->{timecreate},
          body_text  => $text_row->{msg_decoded},
          body_raw   => $text_row->{msg_raw},
          error      => $error,
          meta       => \%props,
          );

    return $msg;
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

        my $uid = LJ::SMS->num_to_uid($owner_num)
            or croak "invalid owner id from number: $owner_num";

        $owneru = LJ::load_userid($uid);
        croak "invalid owner u from number: $owner_num"
            unless LJ::isu($owneru);
    }

    # LJ needs utf8 flag off for all fields, we'll do that
    # here now that we're officially in LJ land.
    $dsms_msg->encode_utf8;

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

sub typemap {
    my $class = shift;

    return LJ::Typemap->new
        ( table      => 'sms_msgproplist',
          classfield => 'name',
          idfield    => 'propid',
          );
}

sub normalize_num {
    my $class = shift;
    my $arg = shift;
    $arg = ref $arg ? $arg->[0] : $arg;

    # add +1 if it's a US number
    $arg = "+1$arg" if $arg =~ /^\d{10}$/;

    return $arg;
}

sub meta {
    my $self = shift;
    my $key  = shift;
    my $val  = shift;

    my $meta = $self->{meta} || {};

    # if a value was specified for a set, handle that here
    if ($key && $val) {

        my %to_set = ($key => $val, @_);

        # if saved to the db, go ahead and write out now
        if ($self->msgid) {

            my $tm    = $self->typemap;
            my $u     = $self->owner_u;
            my $uid   = $u->id;
            my $msgid = $self->id;

            my @vals = ();
            while (my ($k, $v) = each %to_set) {
                next if $v eq $meta->{$k};

                my $propid = $tm->class_to_typeid($k);
                push @vals, ($uid, $msgid, $propid, $v);
            }

            if (@vals) {
                my $bind = join(",", map { "(?,?,?,?)" } (1..@vals/4));

                $u->do("REPLACE INTO sms_msgprop (userid, msgid, propid, propval) VALUES $bind",
                       undef, @vals);
                die $u->errstr if $u->err;
            }
        }

        # update elements in memory
        while (my ($k, $v) = each %to_set) {
            $meta->{$k} = $v;
        }

        # return new set value of the first element passed
        return $meta->{$key};
    }

    # if a specific key was specified, return that element
    # ... otherwise return a hashref of all k/v pairs
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
    $self->{to_uid} = LJ::SMS->num_to_uid($self->{to_num})
        unless exists $self->{to_uid};

    # load user obj if valid uid and return
    my $uid = $self->{to_uid};
    return $uid ? LJ::load_userid($uid) : undef;
}

sub from_num {
    my $self = shift;
    return $self->{from_num};
}

sub from_u {
    my $self = shift;

    # load userid from db unless the cache key exists
    $self->{_from_uid} = LJ::SMS->num_to_uid($self->{from_num})
        unless exists $self->{_from_uid};

    # load user obj if valid uid and return
    my $uid = $self->{_from_uid};
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

sub msgid {
    my $self = shift;
    return $self->{msgid};
}
*id = \&msgid;

sub status {
    my $self = shift;
    my $val  = shift;

    # third argument to call as $self->('error' => $err_str);
    my $val_arg = shift;

    if ($val) {
        croak "invalid value for 'status': $val"
            unless $val =~ /^(?:success|error|unknown)$/;

        if ($self->msgid && $val ne $self->{status}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("UPDATE sms_msg SET status=? WHERE userid=? AND msgid=?",
                         undef, $val, $owner_u->{userid}, $self->msgid);
            die $owner_u->errstr if $owner_u->err;
        }

        # set error string for this message if one was given
        $self->error($val_arg) if $val eq 'error' && $val_arg;

        return $self->{status} = $val;
    }

    return $self->{status};
}

sub error {
    my $self = shift;
    my $errstr = shift;

    if ($errstr) {

        if ($self->msgid && $errstr ne $self->{error}) {
            my $owner_u = $self->owner_u;
            $owner_u->do("REPLACE INTO sms_msgerror SET userid=?, msgid=?, error=?",
                         undef, $owner_u->{userid}, $self->msgid, $errstr);
            die $owner_u->errstr if $owner_u->err;
        }

        return $self->{error} = $errstr;
    }

    return $self->{error};
}

sub is_success {
    my $self = shift;
    return $self->status eq 'success' ? 1 : 0;
}

sub is_error {
    my $self = shift;
    return $self->status eq 'error' ? 1 : 0;
}

sub body_text {
    my $self = shift;

    return $self->{body_text} unless $LJ::IS_DEV_SERVER;

    # shared test gateway requires prefix of "lj " before
    # any message to ensure it is delivered to us
    my $body_text = $self->{body_text};
    $body_text =~ s/^lj\s+//i;
    return $body_text;
}

sub body_raw {
    my $self = shift;
    return $self->{body_raw};
}

sub save_to_db {
    my $self = shift;

    # do nothing if already saved to db
    return 1 if $self->{msgid};

    my $u = $self->owner_u
        or die "no owner object found";
    my $uid = $u->{userid};

    # allocate a user counter id for this messaGe
    my $msgid = LJ::alloc_user_counter($u, "G")
        or die "Unable to allocate msgid for user: " . $self->owner_u->{user};
    
    # insert main sms_msg row
    $u->do("INSERT INTO sms_msg SET userid=?, msgid=?, type=?, status=?, " .
           "to_number=?, from_number=?, timecreate=UNIX_TIMESTAMP()", 
           undef, $uid, $msgid, $self->type, $self->status, 
           $self->to_num, $self->from_num);
    die $u->errstr if $u->err;

    # save blob parts to their table
    $u->do("INSERT INTO sms_msgtext SET userid=?, msgid=?, msg_raw=?, msg_decoded=?",
           undef, $uid, $msgid, $self->body_raw, $self->body_text);
    die $u->errstr if $u->err;

    # save error string if any
    if ($self->error) {
        $u->do("INSERT INTO sms_msgerror SET userid=?, msgid=?, error=?",
               undef, $u->{userid}, $msgid, $self->error);
        die $u->errstr if $u->err;
    }

    # save msgid into this object
    $self->{msgid} = $msgid;

    # write props out to db...
    $self->save_props_to_db;

    return 1;
}

sub save_props_to_db {
    my $self    = shift;
        
    my $tm = $self->typemap;

    my $u     = $self->owner_u;
    my $uid   = $u->id;
    my $msgid = $self->id;

    my @vals = ();
    while (my ($propname, $propval) = each %{$self->meta}) {
        my $propid = $tm->class_to_typeid($propname);
        push @vals => $uid, $msgid, $propid, $propval;
    }

    if (@vals) {
        my $bind = join(",", map { "(?,?,?,?)" } (1..@vals/4));

        $u->do("REPLACE INTO sms_msgprop (userid, msgid, propid, propval) VALUES $bind",
               undef, @vals);
        die $u->errstr if $u->err;
    }

    return 1;
}

sub respond {
    my $self = shift;
    my $body_text = shift;
    my %opts = @_;

    my $resp = LJ::SMS::Message->new
        ( owner     => $self->owner_u,
          from      => $self->to_num,
          to        => $self->from_num,
          body_text => $body_text );

    $resp->send(%opts);

    return $resp;
}

sub send {
    my $self = shift;
    my %opts = @_;

    # FIXME: return 0 doesn't seem good? need to know why?
    return 0 if ! $LJ::DISABLED{sms_quota_check} && ! $opts{no_quota} && $self->to_u && ! $self->to_u->sms_quota_remaining;

    # do not send message to this user unless they are confirmed and active
    return 0 unless $self->to_u && $self->to_u->prop('sms_enabled') eq 'active' || $opts{force};

    if (my $cv = $LJ::_T_SMS_SEND) {
        LJ::run_hook('sms_sent_msg', $self->to_u, %opts) if $self->to_u;
        return $cv->($self);
    }

    my $gw = LJ::sms_gateway()
        or die "unable to instantiate SMS gateway object";

    my $dsms_msg = DSMS::Message->new
        (
         to   => $self->to_num,
         from => $self->from_num,
         body_text => $self->body_text,
         ) or die "unable to construct DSMS::Message to send";

    my $rv = eval { $gw->send_msg($dsms_msg) };

    $self->status($@ ? ('error' => $@) : 'success');

    # FIXME: absorb_dsms type function for these two lines?
    # verify we've set the appropriate message type
    $self->{type} = $dsms_msg->type;
    # ... also metadata
    # FIXME: if the message has already been saved, this
    #        won't properly set 'meta' in the db...
    $self->{meta} = $dsms_msg->meta;

    # this message has been sent, log it to the db
    # FIXME: this the appropriate time?
    $self->save_to_db;

    LJ::run_hook('sms_sent_msg', $self->to_u, %opts);

    return 1;
}

sub should_enqueue { 1 }

sub as_string {
    my $self = shift;
    return "from=$self->{from}, text=$self->{body_text}\n";
}

1;
