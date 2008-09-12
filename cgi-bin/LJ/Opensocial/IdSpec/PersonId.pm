# LJ/Opensocial/IdSpec/PersonId.pm - jop

package LJ::Opensocial::IdSpec::PersonId;

use strict;

our $OWNER = 0;
our $VIEWER = 1;

our @EXPORT_OK = qw( $OWNER $VIEWER );

#####

sub lookup {
  my $p_tag = shift;
  return "OWNER" if $p_tag == $OWNER;
  return "VIEWER" if $p_tag == $VIEWER;
  return "UNDEFINED";
}

#####

1;

# End of file.
