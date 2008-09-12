# LJ/Opensocial/ResponseItem.pm - jop

package LJ::Opensocial::ResponseItem;
use LJ::Opensocial::ResponseItem::Error;

use strict;

#####

sub new {
  my $l_class = shift;
  my $l_self = { 'originalDataRequest' => undef,
                 'requestData' => undef,
                 'errorCode' => 0 };
  bless $l_self;
  return $l_self;
}

#####

sub hadError {
  my $l_self = shift;
  return ($l_self->{errorCode} == 0 ? 0 : 1);
}

#####

sub setError {
  my $l_self = shift;
  my $l_errorCode = shift;
  $l_self->{errorCode} = $l_errorCode;
}

#####

sub setData {
  my $l_self = shift;
  my $l_data = shift;
  $l_self->{requestData} = $l_data;
}

#####

sub getData {
  my $l_self = shift;
  return $l_self->{requestData};
}

#####

sub getErrorCode {
  my $l_self = shift;
  return $l_self->{errorCode};
}

#####

sub getErrorMessage {
  my $l_self = shift;
  return LJ::Opensocial::ResponseItem::Error::getMessage($l_self->{errorCode});
}

#####

sub getOriginalDataRequest {
  my $l_self = shift;
  return $l_self->{originalDataRequest};
}

#####

sub setOriginalDataRequest {
  my $l_self = shift;
  my $l_originalDataRequest = shift;
  $l_self->{originalDataRequest} = $l_originalDataRequest;
}

#####

1;

# End of file.
