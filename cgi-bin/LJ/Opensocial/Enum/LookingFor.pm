# LJ/Opensocial/Enum/LookingFor.pm - jop

package LJ::Opensocial::Enum::LookingFor;

use strict;

our $ACTIVITY_PARTNERS = 0;
our $DATING = 1;
our $FRIENDS = 2;
our $NETWORKING = 3;
our $RANDOM = 4;
our $RELATIONSHIP = 5;

our @EXPORT_OK = qw ( $ACTIVITY_PARTNERS $DATING $FRIENDS
                      $NETWORKING $RANDOM $RELATIONSHIP
                    );

#####

sub lookup {
  my $p_tag = shift;
  return "ACTIVITY_PARTNERS" if $p_tag == $ACTIVITY_PARTNERS; 
  return "DATING" if $p_tag == $DATING;
  return "FRIENDS" if $p_tag == $FRIENDS;
  return "NETWORKING" if $p_tag == $NETWORKING;
  return "RANDOM" if $p_tag == $RANDOM;
  return "RELATIONSHIP" if $p_tag == $RELATIONSHIP;
  return "UNDEFINED";
}

#####

1;

# End of file.
