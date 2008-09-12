# LJ/Opensocial/ResponseItem/Error.pm - jop

package LJ::Opensocial::ResponseItem::Error;

use strict;

our $SUCCESS = 0;
our $UNDEFINED_ERROR = 1;
our $INTERNAL_ERROR = 2;
our $LIMIT_EXCEEDED = 3;
our $NOT_IMPLEMENTED = 4;
our $UNAUTHORIZED = 5;
our $BAD_REQUEST = 6;
our $FORBIDDEN = 7;

our @EXPORT_OK = qw( $BAD_REQUEST $FORBIDDEN $INTERNAL_ERROR
                     $LIMIT_EXCEEDED $NOT_IMPLEMENTED $UNAUTHORIZED
                     $SUCCESS $UNDEFINED_ERROR );

#####

sub lookup {
  my $p_tag = shift;
  return "SUCCESS" if $p_tag == $SUCCESS;
  return "BAD_REQUEST" if $p_tag == $BAD_REQUEST;
  return "FORBIDDEN" if $p_tag == $FORBIDDEN;
  return "INTERNAL_ERROR" if $p_tag == $INTERNAL_ERROR;
  return "LIMIT_EXCEEDED" if $p_tag == $LIMIT_EXCEEDED;
  return "NOT_IMPLEMENTED" if $p_tag == $NOT_IMPLEMENTED;
  return "UNAUTHORIZED" if $p_tag == $UNAUTHORIZED;
  return "UNDEFINED_ERROR";
}

#####

sub getCode {
  my $p_code = shift;
  return $SUCCESS if $p_code eq "SUCCESS";
  return $BAD_REQUEST if $p_code eq "BAD_REQUEST";
  return $FORBIDDEN if $p_code eq "FORBIDDEN";
  return $INTERNAL_ERROR if $p_code eq "INTERNAL_ERROR";
  return $LIMIT_EXCEEDED if $p_code eq "LIMIT_EXCEEDED";
  return $NOT_IMPLEMENTED if $p_code eq "NOT_IMPLEMENTED";
  return $UNAUTHORIZED if $p_code eq "UNAUTHORIZED";
  return $UNDEFINED_ERROR;
}

#####

sub getMessage {
  my $p_tag = shift;
  return "Success."
    if $p_tag == $SUCCESS;
  return "Undefined error."
    if $p_tag == $UNDEFINED_ERROR;
  return "The request was invalid." 
    if $p_tag == $BAD_REQUEST;
  return "The gadget can never have access to the requested data." 
    if $p_tag == $FORBIDDEN;
  return "The request encountered an unexpected condition that " .
         "prevented the request from being fulfilled." 
    if $p_tag == $INTERNAL_ERROR;
  return "The gadget exceeded a quota on the request." 
    if $p_tag == $LIMIT_EXCEEDED;
  return "The container does not support the request that was made." 
    if $p_tag == $NOT_IMPLEMENTED;
  return "The gadget does not have access to the requested data." 
    if $p_tag == $UNAUTHORIZED;
  return "The error message is undefined.";
}

#####

1;

# End of file.
