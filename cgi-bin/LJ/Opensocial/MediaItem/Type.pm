# LJ/Opensocial/MediaItem/Type.pm - jop

package LJ::Opensocial::MediaItem::Type;

use strict;

our $AUDIO = 0;
our $IMAGE = 1;
our $VIDEO = 2;

our @EXPORT_OK = qw( $AUDIO $VIDEO $IMAGE );

#####

sub lookup {
  my $p_tag = shift;
  return "AUDIO" if $p_tag == $AUDIO;
  return "VIDEO" if $p_tag == $VIDEO;
  return "IMAGE" if $p_tag == $IMAGE;
  return "UNDEFINED";
}

#####

1;

# End of file.
