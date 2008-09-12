# LJ/Opensocial/EscapeType.pm - jop

package LJ::OPensocial::EscapeType;

use strict;

our $HTML_ESCAPE = 0;
our $NONE = 1;

our @EXPORT_OK = qw( $HTML_ESCAPE $NONE );

#####

sub lookup {
  my $p_tag = shift;
  return "HTML_ESCAPE" if $p_tag == $HTML_ESCAPE;
  return "NONE" if $p_tag == $NONE;
  return "UNDEFINED";
}

#####

1;

# End of file.
