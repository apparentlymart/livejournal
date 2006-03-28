package LJ::Location;
use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    my $coords = delete $opts{'coords'};
    die if %opts;
    my $self = bless {}, $class;
    $self->set_coords($coords) if $coords;
    return $self;
}

sub set_coords {
    my ($self, $coords) = @_;
    my ($lat, $long);
    if ($coords =~ /^(\d+\.\d+)\s*([NS])\s*,?\s*(\d+\.\d+)\s*([EW])$/i) {
        my ($latpos, $latside, $longpos, $longside) = ($1, uc $2, $3, uc $4);
        $lat  =  $latpos;
        $lat  = -$latpos if $latside eq "S";
        $long =  $longpos;
        $long = -$longpos if $longside eq "W";
    } elsif ($coords =~ /^(-?\d+\.\d+)\s*\,?\s*(-?\d+\.\d+)$/) {
        $lat  = $1;
        $long = $2;
    } else {
        die "Invalid coords format";
    }

    die "Latitude out of range"  if abs $lat > 90;
    die "Longitude out of range" if abs $long > 180;
    $self->{lat}      = $lat;
    $self->{long}     = $long;
    return $self;
}

sub as_posneg_comma {
    my $self = shift;
    return sprintf("%0.04f,%0.04f", $self->{lat}, $self->{long});
}

1;
