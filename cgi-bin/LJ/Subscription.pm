package LJ::Subscription;
use strict;
use warnings;
use Carp qw(croak);

my @subs_fields = qw(userid subid is_dirty journalid etypeid arg1 arg2
                     ntypeid createtime expiretime flags);

# Class method
sub new_from_row {
    my ($class, $row) = @_;

    my $self = bless {%$row}, $class;
    # TODO validate keys of row.
    return $self;
}

sub new_by_id {
    my ($class, $u, $subid) = @_;
    croak "subscriptions_of_user requires a valid 'u' object"
        unless LJ::isu($u);
    croak "invalid subscription id passed"
        unless defined $subid && int($subid) > 0;

    my $row = $u->selectrow_hashref
        ("SELECT userid, subid, is_dirty, journalid, etypeid, " .
         "arg1, arg2, ntypeid, createtime, expiretime, flags " .
         "FROM subs WHERE userid=?", undef $u->{userid}, $subid);
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

sub create {
    my ($class, $u, $info) = @_;

    my $self = $class->new_from_row( $info );
    
    my @columns;
    my @values;
    
    foreach (@subs_fields) {
        if (exists( $info->{$_} )) {
            push @columns, $_;
            push @values, $info->{$_};
        }
    }
    croak( "Extra info defined, (" . join( ', ', keys( %$info ) ) . ")" );
    
    my $sth = $u->prepare( 'INSERT INTO subs (' . join( ',', @columns ) . ')' .
                           'VALUES (' . join( ',', map {'?'} @values ) . ')' );
    $sth->execute( @values );

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

sub event {
    my $self = shift;
    return LJ::Event->new_from_raw_params($self->{etypeid}, $self->{journalid}, $self->{arg1}, $self->{arg2});
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
    my $class = NotificationMethod->class($self->{ntypeid});
    return $class->new_from_subscription($self);
}

sub process {
    my ($self, @events) = @_;
    $self->notification->notify(@events);
}

1;
