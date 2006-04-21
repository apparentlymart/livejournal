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

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    foreach my $k (qw(foo bar baz)) {
        $self->{$k} = delete $opts{$k};
    }
    croak if %opts;
    return $self;
}

# Class method
sub new_from_row {
    my ($class, $row) = @_;

    my $self = bless {%$row}, $class;
    # TODO validate keys of row.
    return $self;
}

sub matches {
    return 1;
    my $self = shift;
    my $event = shift;

#    if ($self->userid == $event->
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

1;
