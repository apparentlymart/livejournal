# LJ/Opensocial/Util/FieldBase.pm - jop

package LJ::Opensocial::Util::FieldBase;
use Data::Dumper;


our $AUTOLOAD;

use strict;

our $m_fields = undef;

#####

sub AUTOLOAD {

  my @l_params = @_;
  my $l_fname = $AUTOLOAD;

  $l_fname =~ /^(.*)\:\:(set)?(.*)$/;
  my $l_module = $1; my $l_set = $2; my $l_tag = $3;
  return "UNDEFINED" unless grep(/^$l_tag$/,@{$m_fields}); 
  return set_tag($l_tag,@l_params) if defined $l_set;
  return get_tag($l_tag); # otherwise a getter
}

#####

sub get_tag {
  my($p_tag) = @_;
  return "Get $p_tag.\n";
}

#####

sub set_tag {
  my($p_tag,$p_value) = @_;
  return "Set $p_tag to $p_value.\n";
}

#####

1;

# End of file.
