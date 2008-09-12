# LJ/Opensocial/Environment/ObjectType.pm - jop

package LJ::Opensocial::Environment::ObjectType;

use strict;

our $ACTIVITY = 0;
our $ADDRESS = 1;
our $BODY_TYPE = 2;
our $EMAIL = 3;
our $FILTER_TYPE = 4;
our $MEDIA_ITEM = 5;
our $MESSAGE = 6;
our $MESSAGE_TYPE = 7;
our $NAME = 8;
our $ORGANIZATION = 9;
our $PERSON = 10;
our $PHONE = 11;
our $SORT_ORDER = 12;
our $URL = 13;

our @EXPORT_OK = qw( $ACTIVITY $ADDRESS $BODY_TYPE $EMAIL $FILTER_TYPE
                     $MEDIA_ITEM $MESSAGE $MESSAGE_TYPE $NAME $ORGANIZATION
                     $PERSON $PHONE $SORT_ORDER $URL
                   );

#####

sub lookup {
  my $p_tag = shift;
  return "ACTIVITY" if $p_tag == $ACTIVITY;
  return "ADDRESS" if $p_tag == $ADDRESS;
  return "BODY_TYPE" if $p_tag == $BODY_TYPE;
  return "EMAIL" if $p_tag == $EMAIL;
  return "FILTER_TYPE" if $p_tag == $FILTER_TYPE;
  return "MEDIA_ITEM" if $p_tag == $MEDIA_ITEM;
  return "MESSAGE" if $p_tag == $MESSAGE;
  return "MESSAGE_TYPE" if $p_tag == $MESSAGE_TYPE;
  return "NAME" if $p_tag == $NAME;
  return "ORGANIZATION" if $p_tag == $ORGANIZATION;
  return "PERSON" if $p_tag == $PERSON;
  return "PHONE" if $p_tag == $PHONE;
  return "SORT_ORDER" if $p_tag == $SORT_ORDER;
  return "URL" if $p_tag == $URL;
  return "UNDEFINED";
}

#####

1;

# End of file.
