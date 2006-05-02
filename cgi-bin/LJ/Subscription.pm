package LJ::Subscription;
use strict;
use warnings;
use Carp qw(croak);
use Class::Autouse qw(
                      LJ::NotificationMethod
                      LJ::Typemap
                      );

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

sub subscriptions_of_user {
    my ($class, $u) = @_;
    croak "subscriptions_of_user requires a valid 'u' object"
        unless LJ::isu($u);

    my $sth = $u->prepare("SELECT userid, subid, is_dirty, journalid, etypeid, " .
                          "arg1, arg2, ntypeid, createtime, expiretime, flags " .
                          "FROM subs WHERE userid=?");
    $sth->execute($u->{userid});
    die $u->errstr if $u->err;

    my @subs;
    while (my $row = $sth->fetchrow_hashref) {
        push @subs, LJ::Subscription->new_from_row($row);
    }
    return @subs;
}


# Class method
sub new_from_row {
    my ($class, $row) = @_;

    my $self = bless {%$row}, $class;
    # TODO validate keys of row.
    return $self;
}

sub create {
    my ($class, $u, %args) = @_;

    # easier way for eveenttype
    if (my $evt = delete $args{'event'}) {
        $evt = "LJ::Event::$evt" unless $evt =~ /^LJ::Event::/;
        $args{etypeid} = LJ::Event->typemap->class_to_typeid($evt);
    }

    # easier way to specify ntypeid
    if (my $ntype = delete $args{'method'}) {
        $ntype = "LJ::NotificationMethod::$ntype" unless $ntype =~ /^LJ::NotificationMethod::/;
        $args{ntypeid} = LJ::NotificationMethod->typemap->class_to_typeid($ntype);
    }

    # easier way to specify journal
    if (my $ju = delete $args{'journal'}) {
        $args{journalid} = $ju->{userid};
    }

    $args{arg1} ||= 0;
    $args{arg2} ||= 0;

    foreach (qw(ntypeid etypeid journalid)) {
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

    return $self;
}

sub id {
    my $self = shift;

    return $self->{subid};
}

sub createtime {
    my $self = shift;
    return $self->{createtime};
}

sub expiretime {
    my $self = shift;
    return $self->{expiretime};
}

sub journalid {
    my $self = shift;
    return $self->{journalid};
}

sub event {
    my $self = shift;
    return LJ::Event->new_from_raw_params($self->{etypeid}, $self->{journalid}, $self->{arg1}, $self->{arg2});
}

sub args {
    my $self = shift;
    return ($self->{arg1}, $self->{arg2});
}

sub ntypeid {
    my $self = shift;
    return $self->{ntypeid};
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
    $self->notification->notify(@events);
}

1;
