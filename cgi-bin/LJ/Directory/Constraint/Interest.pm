package LJ::Directory::Constraint::Interest;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);

# wants intid
sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(intid interest);
    croak "unknown args" if %args;
    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    return undef unless ($args->{int_like} xor $args->{intid});
    return $pkg->new(intid    => $args->{intid},
                     interest => $args->{int_like});
}

sub cache_for { 5 * 60 }

sub intid {
    my $self = shift;
    $self->load_row unless $self->{_loaded_row};
    return $self->{intid} || 0;
}

sub load_row {
    my $self = shift;
    $self->{_loaded_row} = 1;
    my $row;
    my $dbh = LJ::get_db_writer();
    if ($self->{intid}) {
        $row = $dbh->selectrow_hashref("SELECT intid, interest, intcount FROM interests WHERE intid=?",
                                       undef, $self->{intid});
    } elsif ($self->{interest}) {
        $row = $dbh->selectrow_hashref("SELECT intid, interest, intcount FROM interests WHERE interest=?",
                                       undef, $self->{interest});
    }
    $self->{$_} = $row->{$_} foreach (qw(intid interest intcount));
}

sub matching_uids {
    my $self = shift;
    my $db = LJ::get_dbh("directory") || LJ::get_db_reader();
    my @ids = @{ $db->selectcol_arrayref("SELECT userid FROM userinterests WHERE intid=?",
                                         undef, $self->intid) || [] };
    return @ids;

}

1;
