# LJ/Opensocial/CreateActivityPriority.pm - jop

package LJ::Opensocial::CreateActivityPriority;

use strict;

our $HIGH = 0;
our $LOW = 1;

our @EXPORT_OK = qw( $HIGH $LOW );

#####

sub lookup {
  my $p_tag = shift;
  return "HIGH" if $p_tag == $HIGH;
  return "LOW" if $p_tag == $LOW;
  return "UNDEFINED";
}

#####

1;

# End of file.
