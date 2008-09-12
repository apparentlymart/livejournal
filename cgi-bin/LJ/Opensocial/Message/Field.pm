# LJ/Opensocial/Message/Field.pm - jop

package LJ::Opensocial::Message::Field;

use strict;

our @fields = qw {
                   BODY
                   BODY_ID
                   TITLE
                   TITLE_ID
                   TYPE
                 };
1;

our @EXPORT_OK = qw{ $BODY $BODY_ID $TITLE $TITLE_ID $TYPE };

our $BODY = 0;
our $BODY_ID = 1;
our $TITLE = 2;
our $TITLE_ID = 3;
our $TYPE = 4;

#####

sub lookup {
  my $p_tag = shift;
  return "BODY" if $p_tag == $BODY;
  return "BODY_ID" if $p_tag == $BODY_ID;
  return "TITLE" if $p_tag == $TITLE;
  return "TITLE_ID" if $p_tag == $TITLE_ID;
  return "TYPE" if $p_tag == $TYPE;
  return "UNDEFINED";
}

#####

1;

# End of file.
