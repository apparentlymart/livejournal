# LJ/Opensocial/DataRequest/FilterType.pm - jop

package LJ::Opensocial::DataRequest::FilterType;

use strict;

our $ALL = 0;
our $HAS_APP = 1;
our $TOP_FRIENDS = 2;

#####

sub lookup {
  my $p_tag = shift;
  return "ALL" 
    if $p_tag == $LJ::Opensocial::DataRequest::FilterType::ALL;
  return "HAS_APP" 
    if $p_tag == $LJ::Opensocial::DataRequest::FilterType::HAS_APP;
  return "TOP_FRIENDS" 
    if $p_tag == $LJ::Opensocial::DataRequest::FilterType::TOP_FRIENDS;
  return "UNDEFINED";
}

#####

1;

# End of file.
