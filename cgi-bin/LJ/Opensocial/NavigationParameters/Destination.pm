# LJ/Opensocial/NavigationParameters/Destination.pm - jop

package LJ::Opensocial::NavigationParameters::Destination;

use strict;

our $RECIPIENT_DESTINATION = 0;
our $VIEWER_DESTINATION = 1;

our @EXPORT_OK = qw ( $RECIPIENT_DESTINATION $VIEWER_DESTINATION );

#####

sub lookup {
  my $p_tag = shift;
  return "RECIPIENT_DESTINATION" if $p_tag == $RECIPIENT_DESTINATION;
  return "VIEWER_DESTINATION" if $p_tag == $VIEWER_DESTINATION;
  return "UNDEFINED";
}

#####

1;

# End of file.
