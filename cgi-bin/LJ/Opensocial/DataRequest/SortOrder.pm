# LJ/Opensocial/DataRequest/SortOrder.pm - jop

package LJ::Opensocial::DataRequest::SortOrder;

use strict;

our $NAME = 0;
our $TOP_FRIENDS = 1;

our @EXPORT_OK = qw( $NAME $TOP_FRIENDS );

#####

sub lookup {
  my $p_tag = shift;
  return "NAME" if $p_tag == $NAME;
  return "TOP_FRIENDS" if $p_tag == $TOP_FRIENDS;
  return "UNDEFINED";
}

#####

1;

# End of file.
