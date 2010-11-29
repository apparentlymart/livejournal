package LJ::User::PropStorage::Packed;
use strict;
use warnings;

use base qw(LJ::User::PropStorage);

use Carp qw();

sub use_memcache { return; }

sub can_handle {
    my ($class, $propname) = @_;

    my $propinfo = LJ::get_prop( 'user', $propname );
    return 0 unless $propinfo;

    return 0 unless $propinfo->{'datatype'} =~ /^bit/;

    return 1;
}

sub get_bit {
    my ($class, $propname) = @_;

    my $propinfo = LJ::get_prop( 'user', $propname );

    Carp::croak "cannot get userprop info for $propname"
        unless $propinfo;

    if ($propinfo->{'datatype'} =~ /^bit(\d+)$/) {
        return $1;
    }

    Carp::croak "$propname is not a packed userprop";
}

sub get_props {
    my ($class, $u, $props) = @_;

    my %ret;

    foreach my $propname (@$props) {
        my $bit = $class->get_bit($propname);
        $ret{$propname} = ( $u->packed_props & (1 << $bit) ) ? 1 : 0;
    }
}

sub set_props {
    my ($class, $u, $propmap) = @_;

    my $newprops = $u->packed_props;

    foreach my $propname ( keys %$propmap ) {
        my $bit = $class->get_bit($propname);
        if ( $propmap->{$propname} ) {
            $newprops |= (1 << $bit);
        } else {
            $newprops &= ~(1 << $bit);
        }
    }

    $u->set_packed_props($newprops);
}

1;
