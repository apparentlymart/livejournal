package LJ::Message;
use strict;
use Carp qw/ croak /;

use Class::Autouse qw(
                      LJ::Typemap
                      );

my %singletons = (); # journalid-msgid


sub new {
    my ($class, $opts) = @_;

    my $self = {};

    # fields
    foreach my $f (qw(msgid journalid otherid subject body type parent_msgid
                      timesent userpic)) {
        $self->{$f} = delete $opts->{$f} if exists $opts->{$f};
    }

    # unknown fields
    croak("Invalid fields: " . join(",", keys %$opts)) if (%$opts);

    bless $self, $class;
    return $self;
}

sub load {
    my ($msgid, $uid) = @_;

    return get_singleton($msgid, $uid) if (get_singleton($msgid, $uid));
    # load bare instance of object
    return __PACKAGE__->new({msgid => $msgid, journalid => $uid});
}

sub send {
    my $self = shift;

    # Set remaining message properties
    # M is the designated character code for Messaging counter
    my $msgid = LJ::alloc_global_counter('M')
                or croak("Unable to allocate global message id");
    $self->set_msgid($msgid);
    $self->set_timesent(time());

    # Send message by writing to DB and triggering event
    if ($self->save_to_db) {
        $self->_send_msg_event;
        return 1;
    } else {
        return 0;
    }
}

sub _send_msg_event {
    my ($self) = @_;

    my $msgid = $self->msgid;
    my $ou = $self->_orig_u;
    my $ru = $self->_rcpt_u;
    LJ::Event::UserMessageSent->new($ou, $msgid)->fire;
    LJ::Event::UserMessageRecvd->new($ru, $msgid)->fire;
}

# Write message data to tables while ensuring everything completes
sub save_to_db {
    my ($self) = @_;

    my $orig_u = $self->_orig_u;
    my $rcpt_u = $self->_rcpt_u;

    # Users on the same cluster share the DB handle so only a single
    # transaction will exist
    my $same_cluster = $orig_u->clusterid eq $rcpt_u->clusterid;

    # Begin DB Transaction
    my $o_rv = $orig_u->begin_work;
    my $r_rv = $rcpt_u->begin_work unless $same_cluster;

    # Write to DB
    my $orig_write = $self->_save_sender_message;
    my $rcpt_write = $self->_save_recipient_message;
    if ($orig_write && $rcpt_write) {
        $orig_u->commit;
        $rcpt_u->commit unless $same_cluster;
        return 1;
    } else {
        $orig_u->rollback;
        $rcpt_u->rollback unless $same_cluster;
        return 0;
    }

}

sub _save_sender_message {
    my ($self) = @_;

    my $orig_u = $self->_orig_u;

    return $self->_save_db_message('out');
}
sub _save_recipient_message {
    my ($self) = @_;

    my $rcpt_u = $self->_rcpt_u;

    return $self->_save_db_message('in');
}
sub _save_db_message {
    my ($self, $type) = @_;

    # Message is being sent or received
    # set userid and otherid as appropriate
    my ($u, $userid, $otherid);
    if ($type eq 'out') {
        $u = $self->_orig_u;
        $userid = $self->journalid;
        $otherid = $self->otherid;
    } elsif ($type eq 'in') {
        $u = $self->_rcpt_u;
        $userid = $self->otherid;
        $otherid = $self->journalid;
    } else {
        croak("Invalid 'type' passed into _save_db_message");
    }

    my $msg_sql = _generate_msg_write();
    my $msgtxt_sql = _generate_msgtxt_write();

    return 0 unless $self->_save_msg_row_to_db($u, $userid, $type, $otherid);
    return 0 unless $self->_save_msgtxt_row_to_db($u, $userid);
    return 0 unless $self->_save_msgprop_row_to_db($u, $userid);

    return 1;
}

sub _save_msg_row_to_db {
    my ($self, $u, $userid, $type, $otherid) = @_;

    my $sql = "INSERT INTO usermsg (journalid, msgid, type, parent_msgid, " .
              "otherid, timesent) VALUES (?,?,?,?,?,?)";

    $u->do($sql,
           undef,
           $userid,
           $self->msgid,
           $type,
           $self->parent_msgid,
           $otherid,
           $self->timesent,
          );

    if ($u->err) {
        warn($u->errstr);
        return 0;
    }

    return 1;
}

sub _save_msgtxt_row_to_db {
    my ($self, $u, $userid) = @_;

    my $sql = "INSERT INTO usermsgtext (journalid, msgid, subject, body) " .
              "VALUES (?,?,?,?)";

    $u->do($sql,
           undef,
           $userid,
           $self->msgid,
           $self->subject,
           $self->body,
          );
    if ($u->err) {
        warn($u->errstr);
        return 0;
    }

    return 1;
}

sub _save_msgprop_row_to_db {
    my ($self, $u, $userid) = @_;

    my $propval = $self->userpic;

    if ($propval) {
        my $tm = $self->typemap;
        my $propid = $tm->class_to_typeid('userpic');
        my $sql = "INSERT INTO usermsgprop (journalid, msgid, propid, propval) " .
                  "VALUES (?,?,?,?)";

        $u->do($sql,
               undef,
               $userid,
               $self->msgid,
               $propid,
               $propval,
              );
        if ($u->err) {
            warn($u->errstr);
            return 0;
        }
    }

    return 1;
}

# TODO deprecated
sub _generate_msg_write {
    my $opts = shift;

    my $sql = "INSERT INTO usermsg (journalid, msgid, type, parent_msgid, " .
              "otherid, timesent) VALUES (?,?,?,?,?,?)";
    return $sql;
}

# TODO deprecated
sub _generate_msgtxt_write {
    my $opts = shift;

    my $sql = "INSERT INTO usermsgtext (msgid, subject, body) " .
              "VALUES (?,?,?)";
    return $sql;
}


#############
#  Accessors
#############
sub journalid {
    my $self = shift;

    return $self->{journalid};
}

sub msgid {
    my $self = shift;

    return $self->{msgid};
}

sub _orig_u {
    my $self = shift;

    return LJ::want_user($self->journalid);
}

sub _rcpt_u {
    my $self = shift;

    return LJ::want_user($self->otherid);
}

sub type {
    my $self = shift;

    __PACKAGE__->preload_msg_rows([ $self ]) unless $self->{_loaded_msg_row};
    return $self->{type};
}

sub parent_msgid {
    my $self = shift;

    __PACKAGE__->preload_msg_rows([ $self ]) unless $self->{_loaded_msg_row};
    return $self->{parent_msgid};
}

sub otherid {
    my $self = shift;

    __PACKAGE__->preload_msg_rows([ $self ]) unless $self->{_loaded_msg_row};
    return $self->{otherid};
}

sub other_u {
    my $self = shift;

    __PACKAGE__->preload_msg_rows([ $self ]) unless $self->{_loaded_msg_row};
    return LJ::want_user($self->{otherid});
}

sub timesent {
    my $self = shift;

    __PACKAGE__->preload_msg_rows([ $self ]) unless $self->{_loaded_msg_row};
    return $self->{timesent};
}

sub subject {
    my $self = shift;

    __PACKAGE__->preload_msgtext_rows([ $self ]) unless $self->{_loaded_msgtext_row};
    return $self->{subject};
}

sub body {
    my $self = shift;

    __PACKAGE__->preload_msgtext_rows([ $self ]) unless $self->{_loaded_msgtext_row};
    return $self->{body};
}

sub userpic {
    my $self = shift;

    __PACKAGE__->preload_msgprop_rows([ $self ]) unless $self->{_loaded_msgprop_row};
    return $self->{userpic};
}

#############
#  Setters
#############

sub set_msgid {
    my ($self, $val) = @_;

    $self->{msgid} = $val;
}

sub set_timesent {
    my ($self, $val) = @_;

    $self->{timesent} = $val;
}

###################
#  Object Methods
###################

sub absorb_row {
    my ($self, $table, %row) = @_;

    foreach (qw(journalid type parent_msgid otherid timesent state subject
                body userpic)) {
        if (exists $row{$_}) {
            $self->{$_} = $row{$_};
            $self->{"_loaded_${table}_row"} = 1;
        }
    }
    $self->set_singleton;
}

sub set_singleton {
    my ($self) = @_;

    my $msgid = $self->msgid;
    my $uid = $self->journalid;

    if ($msgid && $uid) {
        $singletons{"$uid-$msgid"} = $self;
    }
}

# Can user reply to this message
# Return true if user received a matching message with type 'in'
sub can_reply {
    my ($self, $msgid, $remote_id) = @_;

    if ($self->journalid == $remote_id &&
        $self->msgid == $msgid &&
        $self->type eq 'in') {
        return 1;
    }

    return 0;
}

###################
#  Class Methods
###################

sub reset_singletons {
    %singletons = ();
}

sub get_singleton {
    my ($msgid, $uid) = @_;

    return $singletons{"$uid-$msgid"};
}

sub preload_rows {
    my ($class, $table, $msglist) = @_;
    foreach my $msg (@$msglist) {
        next if $msg->{"_loaded_${table}_row"};

        my $msgid = $msg->msgid;
        my $journalid = $msg->journalid;
        my $row = eval "${class}::_get_${table}_row($msgid, $journalid)";
        die $@ if $@;
        next unless $row;

        # absorb row into given LJ::Message object
        $msg->absorb_row($table, %$row);
    }
}

sub preload_msg_rows {
    my ($class, $msglist) = @_;
    $class->preload_rows("msg", $msglist);
}

sub preload_msgtext_rows {
    my ($class, $msglist) = @_;
    $class->preload_rows("msgtext", $msglist);
}

sub preload_msgprop_rows {
    my ($class, $msglist) = @_;
    $class->preload_rows("msgprop", $msglist);
}

sub _get_msg_row {
    my ($msgid, $uid) = @_;

    my $u = LJ::want_user($uid);
    croak("Can't get messages without user object in _get_msg_row") unless $u;

    my $memkey = [$uid, "msg:$uid:$msgid"];
    my ($row, $item);

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{'journalid', 'type', 'parent_msgid', 'otherid', 'timesent'} = unpack("NNNNN", $row);
        return $item;
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sql = "SELECT journalid, type, parent_msgid, otherid, timesent " .
              "FROM usermsg WHERE msgid=? AND journalid=?";

    $item = $db->selectrow_hashref($sql, undef, $msgid, $uid);
    return undef unless $item;
    $item->{'msgid'} = $msgid;

    $row = pack("NNNNN", $item->{'journalid'}, $item->{'type'},
                $item->{'parent_msgid'}, $item->{'otherid'}, $item->{'timesent'});

    # TODO Uncomment the following line to enable memcaching
    #LJ::MemCache::set($memkey, $row);

    return $item;
}

sub _get_msgtext_row {
    my ($msgid, $uid) = @_;

    my $u = LJ::want_user($uid);
    croak("Can't get messages without user object in get_msgtext_row") unless $u;

    my $memkey = [$uid, "msgtext:$uid:$msgid"];
    my ($row, $item);

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{'subject', 'body'} = unpack("NNNNN", $row);
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $sql = "SELECT subject, body FROM usermsgtext WHERE msgid=? AND journalid=?";

    $item = $db->selectrow_hashref($sql, undef, $msgid, $uid);
    return undef unless $item;
    $item->{'msgid'} = $msgid;

    $row = pack("NNNNN", $item->{'subject'}, $item->{'body'});

    # TODO Uncomment the following line to enable memcaching
    #LJ::MemCache::set($memkey, $row);

    return $item;
}

sub _get_msgprop_row {
    my ($msgid, $uid) = @_;

    my $u = LJ::want_user($uid);
    croak("Can't get messages without user object in get_msgprop_row") unless $u;

    my $memkey = [$uid, "msgprop:$uid:$msgid"];
    my ($row, $item);

    $row = LJ::MemCache::get($memkey);

    if ($row) {
        @$item{'userpic'} = unpack("NNNNN", $row);
    }

    my $db = LJ::get_cluster_def_reader($u);
    return undef unless $db;

    my $tm = __PACKAGE__->typemap;
    my $propid = $tm->class_to_typeid('userpic');
    my $sql = "SELECT propval FROM usermsgprop " .
              "WHERE journalid=? and msgid=? and propid=?";

    $item = $db->selectrow_hashref($sql, undef, $uid, $msgid, $propid);
    return undef unless $item;
    $item->{'msgid'} = $msgid;
    $item->{'userpic'} = $item->{'propval'};

    $row = pack("NNNNN", $item->{'userpic'});

    # TODO Uncomment the following line to enable memcaching
    #LJ::MemCache::set($memkey, $row);

    return $item;
}

# get the typemap for usermsprop
sub typemap {
    my $self = shift;

    return LJ::Typemap->new(
        table       => 'usermsgproplist',
        classfield  => 'name',
        idfield     => 'propid',
    );
}

1;
