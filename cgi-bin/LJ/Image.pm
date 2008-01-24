package LJ::Image;
use strict;
use Carp qw(croak);
use Class::Autouse qw( Image::Size );

# given an image and some dimensions, will return the dimensions that the image
# should be if it was resized to be no greater than the given dimensions
# (keeping proportions correct).
#
# default dimensions to resize to are:
# 320x240 (for a horizontal image)
# 240x320 (for a vertical image)
# 240x240 (for a square image)
sub get_dimensions_of_resized_image {
    my $class = shift;
    my $imageref = shift;
    my %opts = @_;

    my $given_width = $opts{width} || 320;
    my $given_height = $opts{height} || 240;

    my ($width, $height) = Image::Size::imgsize($imageref);
    my $percentage = 1;

    if ($width > $height) {
        if ($width > $given_width) {
            $percentage = $given_width / $width;
        } elsif ($height > $given_height) {
            $percentage = $given_height / $height;
        }
    } elsif ($height > $width) {
        if ($width > $given_height) {
            $percentage = $given_height / $width;
        } elsif ($height > $given_width) {
            $percentage = $given_width / $height;
        }
    } else { # $width == $height
        my $min = $given_width < $given_height ? $given_width : $given_height;
        if ($width > $min) {
            $percentage = $min / $width;
        }
    }

    $width = int($width * $percentage);
    $height = int($height * $percentage);

    return ( width => $width, height => $height );
}

1;
