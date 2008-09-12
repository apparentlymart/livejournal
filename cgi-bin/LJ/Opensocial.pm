# LJ::Opensocial,  LJ/Opensocial.pm, jop

package LJ::Opensocial;
use LJ::Opensocial::Activity;
use LJ::Opensocial::DataRequest;
use LJ::Opensocial::IdSpec;
use LJ::Opensocial::MediaItem;
use LJ::Opensocial::NavigationParameters;
use LJ::Opensocial::ResponseItem;

use strict;

#####

# All of the methods in this class are static

#####

sub getEnvironment {
  # gets the current environment for this gadget
  return *LJ::Opensocial::Environment;
}

#####

sub hasPermission {
  # Returns true if the current gadget has access to the specified permission
  my $p_permission = shift;
  ## TODO
}

#####

sub newActivity {
  # Creates an activity object which represents an activity on the server
  my $p_params = shift;
  return LJ::Opensocial::Activity->new($p_params);
}

#####
sub newDataRequest {
  # Creates a data request object to use for sending and fetching data 
  # from the server.
  return LJ::Opensocial::DataRequest->new();
}

#####

sub newIdSpec {
  # Creates an IdSpec object
  my $p_params = shift;
  return LJ::Opensocial::IdSpec->new($p_params);
}

#####
sub newMediaItem {
  # Creates a media item
  my($p_mimeType, $p_url, $p_opt_params) = @_;
  return LJ::Opensocial::MediaItem->new($p_mimeType,$p_url,$p_opt_params);
}

#####

sub newMessage {
  # Create a new Message object 
  my ($p_body, $p_opt_params) = @_;
  return LJ::Opensocial::Message->new($p_body,$p_opt_params);
}

#####

sub newNavigationParameters {
  # Creates a NavigationParameters object
  my $p_parameters = shift;
  return LJ::Opensocial::NavigationParameters->new($p_parameters);
}

#####

sub requestCreateActivity {
  # Takes an activity and tries to create it without waiting for the 
  # operation to complete
  my($p_activity,$p_priority,$p_opt_callback) = @_;
  ## TODO
}

#####

sub requestPermission {
  # Requests the user to grant access to the specified permissions
  my($p_permissions,$p_reason,$p_opt_params) = @_;
  ## TODO
}

#####

sub requestSendMessage {
  # sends the message to the specified users
  my($p_recipients,$p_message,$p_opt_callback,$p_opt_params) = @_;
  my $l_responseObject = $p_message->send($p_recipients);
  &{$p_opt_callback}($l_responseObject);
}

#####

sub requestShareApp {
  # requests the container to share this gadget with the named users
  my($p_recipients,$p_reason,$p_opt_callback,$p_opt_params) = @_;
  # TODO
}

#####

1;

# End of file.
