package LJ::Subscription;
use strict;
use warnings;
use Carp qw(croak);

my @subs_fields = qw(
userid    
subid     
is_dirty  
journalid 
etypeid   
arg1      
arg2      
ntypeid   
createtime
expiretime
flags     
);

# Class method
sub new_from_row {
    my ($class, $row) = @_;

    my $self = bless {%$row}, $class;
    # TODO validate keys of row.
    return $self;
}

sub matches {
    my $self = shift;
    my $event = shift;

    if (
        $self->{etypeid} == $event->{etypeid} and
        $self->{journalid} == $event->{journalid} and
        $self->{arg1} == $event->{arg1} and
        $self->{arg2} == $event->{arg2}
    ) {
        return 1;
    }
    else {
        return 0;
    }
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
    my $class = NotificationMethod->class( $self->{ntypeid} );
    return $class->new_from_subscription( $self );
}

1;
