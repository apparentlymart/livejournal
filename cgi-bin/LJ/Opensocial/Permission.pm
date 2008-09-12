# LJ/Opensocial/Permission.pm - jop

package LJ::Opensocial::Permission;

use strict;

our $VIEWER = 0;

our @EXPORT_OK = qw( $VIEWER );

#####

sub lookup {
  my $p_tag = shift;
  return "VIEWER" if $p_tag == $VIEWER;
  return $LJ::Opensocial::Util::String::UNDEFINED_FIELD;
}

#####

1;

# End of file.
