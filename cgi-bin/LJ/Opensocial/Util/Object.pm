# LJ/Opensocial/Util/Object.pm - jop

package LJ::Opensocial::Util::Object;

use strict;

#####

sub new {
  my $m_class = shift;
  my $m_ref = {};
  bless $m_ref,$m_class;
  return $m_ref;
}

#####

sub setField {
  my($l_self,$l_field,$l_data) = @_;

  $l_self->{$l_field} = $l_data;
  (shift)->{(shift)} = shift;
}

#####

sub getField {
  my($l_self,$l_field) = @_;
  if (defined $l_self->{$l_field}) {
    return $l_self->{$l_field};
  }
  return $LJ::Opensocial::Util::String::UNDEFINED_FIELD;
}

#####

1;

# End of file.

