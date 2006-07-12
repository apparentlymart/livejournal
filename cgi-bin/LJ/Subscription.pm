package LJ::Subscription;
use strict;
use Carp qw(croak confess);
use Class::Autouse qw(
                      LJ::NotificationMethod
                      LJ::Typemap
                      LJ::Subscription::Pending
                      );

use constant {
              INACTIVE => 1 << 0,
              };

my @subs_fields = qw(userid subid is_dirty journalid etypeid arg1 arg2
                     ntypeid createtime expiretime flags);

sub new_by_id {
    my ($class, $u, $subid) = @_;
    croak "subscriptions_of_user requires a valid 'u' object"
        unless LJ::isu($u);
    croak "invalid subscription id passed"
        unless defined $subid && int($subid) > 0;

    my $row = $u->selectrow_hashref
        ("SELECT userid, subid, is_dirty, journalid, etypeid, " .
         "arg1, arg2, ntypeid, createtime, expiretime, flags " .
         "FROM subs WHERE userid=? AND subid=?", undef, $u->{userid}, $subid);
    die $u->errstr if $u->err;

    return $class->new_from_row($row);
}

sub freeze {
    my $self = shift;
    return "subid-" . $self->owner->{userid} . '-' . $self->id;
}

# can return either a LJ::Subscription or LJ::Subscription::Pending object
sub thaw {
    my ($class, $data, $u, $POST) = @_;

    # valid format?
    return undef unless ($data =~ /^(pending|subid) - $u->{userid} .+ ?(-old)?$/x);

    my ($type, $userid, $subid) = split("-", $data);

    return LJ::Subscription::Pending->thaw($data, $u, $POST) if $type eq 'pending';
    die "Invalid subscription data type: $type" unless $type eq 'subid';

    unless ($u) {
        my $subuser = LJ::load_userid($userid);
        die "no user" unless $subuser;
        $u = LJ::get_authas_user($subuser);
        die "Invalid user $subuser->{user}" unless $u;
    }

    return $class->new_by_id($u, $subid);
}

sub pending { 0 }
sub default_selected { 1 }

sub subscriptions_of_user {
    my ($class, $u) = @_;
    croak "subscriptions_of_user requires a valid 'u' object"
        unless LJ::isu($u);

    return @{$u->{_subscriptions}} if defined $u->{_subscriptions};

    my $sth = $u->prepare("SELECT userid, subid, is_dirty, journalid, etypeid, " .
                          "arg1, arg2, ntypeid, createtime, expiretime, flags " .
                          "FROM subs WHERE userid=?");
    $sth->execute($u->{userid});
    die $u->errstr if $u->err;

    my @subs;
    while (my $row = $sth->fetchrow_hashref) {
        push @subs, LJ::Subscription->new_from_row($row);
    }

    $u->{_subscriptions} = \@subs;

    return @subs;
}

# Class method
# Look for a subscription matching the parameters: journal/journalid,
#   ntypeid/method, event/etypeid, arg1, arg2
# Returns a list of subscriptions for this user matching the parameters
sub find {
    my ($class, $u, %params) = @_;

    my ($etypeid, $ntypeid, $journal, $arg1, $arg2);

    if (my $evt = delete $params{event}) {
        $etypeid = LJ::Event->event_to_etypeid($evt);
    }

    if (my $nmeth = delete $params{method}) {
        $ntypeid = LJ::NotificationMethod->method_to_ntypeid($nmeth);
    }

    $etypeid ||= delete $params{etypeid};
    $ntypeid ||= delete $params{ntypeid};

    my $journalid = delete $params{journalid};
    $journal   = LJ::want_user(delete $params{journal});

    unless (defined $journalid) {
        $journalid = defined $journal ? $journal->{userid} : undef;
    }

    $arg1 = delete $params{arg1};
    $arg2 = delete $params{arg2};

    croak "Invalid parameters passed to ${class}->find" if keys %params;

    return () if defined $arg1 && $arg1 =~ /\D/;
    return () if defined $arg2 && $arg2 =~ /\D/;

    my @subs = $u->subscriptions;

    # filter subs on each parameter
    @subs = grep { $_->journalid == $journalid }         @subs if defined $journalid;
    @subs = grep { $_->ntypeid   == $ntypeid }           @subs if $ntypeid;
    @subs = grep { $_->etypeid   == $etypeid }           @subs if $etypeid;

    @subs = grep { $_->arg1 == $arg1 }                   @subs if defined $arg1;
    @subs = grep { $_->arg2 == $arg2 }                   @subs if defined $arg2;

    return @subs;
}

# Instance method
# Remove this subscription
sub delete {
    my $self = shift;

    my $subid = $self->id
        or croak "Invalid subsciption";

    my $u = $self->owner;

    # delete from cache in user
    undef $u->{_subscriptions};

    return $u->do("DELETE FROM subs WHERE subid=?", undef, $subid);
}

# Class method
sub new_from_row {
    my ($class, $row) = @_;

    return undef unless $row;
    my $self = bless {%$row}, $class;
    # TODO validate keys of row.
    return $self;
}

sub create {
    my ($class, $u, %args) = @_;

    # easier way for eveenttype
    if (my $evt = delete $args{'event'}) {
        $args{etypeid} = LJ::Event->event_to_etypeid($evt);
    }

    # easier way to specify ntypeid
    if (my $ntype = delete $args{'method'}) {
        $args{ntypeid} = LJ::NotificationMethod->method_to_ntypeid($ntype);
    }

    # easier way to specify journal
    if (my $ju = delete $args{'journal'}) {
        $args{journalid} = $ju->{userid} if $ju;
    }

    $args{arg1} ||= 0;
    $args{arg2} ||= 0;

    $args{journalid} ||= 0;

    foreach (qw(ntypeid etypeid)) {
        croak "Required field '$_' not found in call to $class->create" unless defined $args{$_};
    }
    foreach (qw(userid subid createtime)) {
        croak "Can't specify field '$_'" if defined $args{$_};
    }

    my $subid = LJ::alloc_user_counter($u, 'E')
        or die "Could not alloc subid for user $u->{user}";

    $args{subid}      = $subid;
    $args{userid}     = $u->{userid};
    $args{createtime} = time();

    my $self = $class->new_from_row( \%args );

    my @columns;
    my @values;

    foreach (@subs_fields) {
        if (exists( $args{$_} )) {
            push @columns, $_;
            push @values, delete $args{$_};
        }
    }

    croak( "Extra args defined, (" . join( ', ', keys( %args ) ) . ")" ) if keys %args;

    my $sth = $u->prepare( 'INSERT INTO subs (' . join( ',', @columns ) . ')' .
                           'VALUES (' . join( ',', map {'?'} @values ) . ')' );
    $sth->execute( @values );
    LJ::errobj($u)->throw if $u->err;

    $u->{_subscriptions} ||= [];
    push @{$u->{_subscriptions}}, $self;

    return $self;
}

# returns a hash of arguments representing this subscription (useful for passing to
# other functions, such as find)
sub sub_info {
    my $self = shift;
    return (
            journalid => $self->journalid,
            etypeid   => $self->etypeid,
            ntypeid   => $self->ntypeid,
            arg1      => $self->arg1,
            arg2      => $self->arg2,
            );
}

# returns a nice HTML description of this current subscription
sub as_html {
    my $self = shift;

    my $evtclass = LJ::Event->class($self->etypeid);
    return undef unless $evtclass;
    return $evtclass->subscription_as_html($self);
}

sub activate {
    my $self = shift;
    $self->clear_flag(INACTIVE);
}

sub deactivate {
    my $self = shift;
    $self->set_flag(INACTIVE);
}

sub set_flag {
    my ($self, $flag) = @_;

    my $flags = $self->flags;

    # don't bother if flag already set
    return if $flags & $flag;

    $flags |= $flag;

    $self->set_flags($flags);
}

sub clear_flag {
    my ($self, $flag) = @_;

    my $flags = $self->flags;

    # don't bother if flag already cleared
    return unless $flags & $flag;

    # clear the flag
    $flags &= ~$flag;

    $self->set_flags($flags);
}

sub set_flags {
    my ($self, $flags) = @_;

    $self->owner->do("UPDATE subs SET flags=? WHERE userid=?", undef, $self->owner->userid);
    $self->{flags} = $flags;
}

sub id {
    my $self = shift;

    return $self->{subid};
}

sub createtime {
    my $self = shift;
    return $self->{createtime};
}

sub flags {
    my $self = shift;
    return $self->{flags} || 0;
}

sub active {
    my $self = shift;
    return ! $self->flags && INACTIVE;
}

sub expiretime {
    my $self = shift;
    return $self->{expiretime};
}

sub journalid {
    my $self = shift;
    return $self->{journalid};
}

sub journal {
    my $self = shift;
    return LJ::load_userid($self->{journalid});
}

sub arg1 {
    my $self = shift;
    return $self->{arg1};
}

sub arg2 {
    my $self = shift;
    return $self->{arg2};
}

sub ntypeid {
    my $self = shift;
    return $self->{ntypeid};
}

sub method {
    my $self = shift;
    return LJ::NotificationMethod->class($self->ntypeid);
}

sub notify_class {
    my $self = shift;
    return LJ::NotificationMethod->class($self->{ntypeid});
}

sub etypeid {
    my $self = shift;
    return $self->{etypeid};
}

sub event_class {
    my $self = shift;
    return LJ::Event->class($self->{etypeid});
}

# returns the owner (userid) of the subscription
sub userid {
    my $self = shift;
    return $self->{userid};
}

sub owner {
    my $self = shift;
    return LJ::load_userid($self->{userid});
}

sub dirty {
    my $self = shift;
    return $self->{is_dirty};
}

sub notification {
    my $self = shift;
    my $class = LJ::NotificationMethod->class($self->{ntypeid});
    return $class->new_from_subscription($self);
}

sub process {
    my ($self, @events) = @_;
    return $self->notification->notify(@events);
}

sub unique {
    my $self = shift;

    my $note = $self->notification or return undef;
    return $note->unique . ':' . $self->owner->{user};
}

# returns true if two subscriptions are equivilant
sub equals {
    my ($self, $other) = @_;

    return 1 if $self->id == $other->id;

    my $match = $self->ntypeid == $other->ntypeid &&
        $self->etypeid == $other->etypeid;

    $match &&= $other->arg1 && ($self->arg1 == $other->arg1) if $self->arg1;
    $match &&= $other->arg2 && ($self->arg2 == $other->arg2) if $self->arg2;

    $match &&= $self->journalid == $other->journalid;

    return $match;
}

package LJ::Error::Subscription::TooMany;
sub fields { qw(subscr u); }

sub as_html { $_[0]->as_string }
sub as_string {
    my $self = shift;
    my $max = $self->field('u')->get_cap('subscriptions');
    return 'The subscription "' . $self->field('subscr')->as_html . '" was not saved because you have' .
        " reached your limit of $max subscriptions";
}


1;
