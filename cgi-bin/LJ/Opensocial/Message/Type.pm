# LJ/Opensocial/Message/Type.pm - jop

package LJ::Opensocial::Message::Type;

use strict;

our $EMAIL = 0;
our $NOTIFICATION = 0;
our $PRIVATE_MESSAGE = 0;
our $PUBLIC_MESSAGE = 0;

our @EXPORT_OK = qw( $EMAIL $NOTIFICATION $PRIVATE_MESSAGE $PUBLIC_MESSAGE );

#####

sub lookup {
  my $p_tag = shift;
  return "EMAIL" if $p_tag == $EMAIL;
  return "NOTIFICATION" if $p_tag == $NOTIFICATION;
  return "PRIVATE_MESSAGE" if $p_tag == $PRIVATE_MESSAGE;
  return "PUBLIC_MESSAGE" if $p_tag == $PUBLIC_MESSAGE;
  return "UNDEFINED";
}

#####

1;

# End of file.
