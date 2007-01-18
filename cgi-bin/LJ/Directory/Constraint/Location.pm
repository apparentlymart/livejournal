package LJ::Directory::Constraint::Location;
use strict;
use warnings;
use base 'LJ::Directory::Constraint';
use Carp qw(croak);
use LJ::Directory::MajorRegion;
use LJ::Directory::SetHandle::MajorRegion;

sub new {
    my ($pkg, %args) = @_;
    my $self = bless {}, $pkg;
    $self->{$_} = delete $args{$_} foreach qw(country state city);
    croak "unknown args" if %args;

    return $self;
}

sub new_from_formargs {
    my ($pkg, $args) = @_;
    my $cn = $args->{loc_cn};
    my $st = $args->{loc_st};
    return undef unless $cn || $st;
    $cn ||= "US";
    $cn = uc $cn;

    if ($cn eq "US" && length($st) > 2) {
        my $dbr = LJ::get_db_reader();
        $st = $dbr->selectrow_array("SELECT code FROM codes WHERE type='state' AND item=?", undef, $st);
        die "Unknown state: " . LJ::ehtml($st) unless $st;
    }

    $st = uc($st || "") if $cn eq "US";

    return $pkg->new(country => $cn,
                     state   => $st,
                     city    => $args->{loc_ci});

}

sub cached_sethandle {
    my ($self) = @_;
    my @regids = LJ::Directory::MajorRegion->region_ids($self->{country},
                                                        $self->{state},
                                                        $self->{city});
    if (@regids) {
        return LJ::Directory::SetHandle::MajorRegion->new(@regids);
    }

    return undef;
}

sub sethandle {
    die "CURRENTLY UNIMPLEMENTED: $_[0]\->sethandle";
}

1;
