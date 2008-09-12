# LJ/Opensocial/Enum/Presence.pm - jop

package LJ::Opensocial::Enum::Presence;

use strict;

our $AWAY = 0;
our $CHAT = 1;
our $DND = 2;
our $OFFLINE = 3;
our $ONLINE = 4;
our $XA = 5;

our @EXPORT_OK = qw( $AWAY $CHAT $DND $OFFLINE $ONLINE $XA );

#####

sub lookup {
  my $p_tag = shift;
  return "AWAY" if $p_tag == $AWAY;
  return "CHAT" if $p_tag == $CHAT;
  return "DND" if $p_tag == $DND;
  return "OFFLINE" if $p_tag == $OFFLINE;
  return "ONLINE" if $p_tag == $ONLINE;
  return "XA" if $p_tag == $XA;
  return "UNDEFINED";
}

#####

1;

# End of file.
