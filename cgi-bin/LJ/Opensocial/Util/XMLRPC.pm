# LJ/Opensocial/Util/XMLRPC.pm - jop

package LJ::Opensocial::Util::XMLRPC;
use LJ::Opensocial::Util::Object;
use Frontier::Client;

our @ISA = (LJ::Opensocial::Util::Object);
use strict;

our $AUTOLOAD;

##### Common routines...

sub AUTOLOAD { # setters and getters

  my ($l_self,$l_value) = @_;

  $AUTOLOAD =~ /^(?:.*)\:\:(set)?([^\:]*)$/;
  my $l_set = $1; my $l_tag = uc $2;

  $l_self->{$l_tag} = $l_value if defined $l_set;
  return $l_self->{$l_tag}; # otherwise a getter
}

##### 

sub call {
  my ($l_self,$l_method,$l_params) = @_;
  if (! defined $l_self->{XMLRPCSERVER}) {
    $l_self->{XMLRPCSERVER} = Frontier::Client->new(
                                'url' => $l_self->Url(),
                                'debug' => $l_self->Debug() 
                              );
  }
  my $l_result = undef;
  eval {
    $l_result = $l_self->{XMLRPCSERVER}->call($l_method,$l_params);
  };
  $l_result = $l_self->parseErrorCode($@) if $@;
  return $l_result;
}

#####

sub parseErrorCode {
  my ($l_self,$l_errorString) = @_;
  $l_errorString =~ /\s(\d+)\:/;
  my $l_errorCode = $1;
  my $l_errorMessage = $LJ::Opensocial::ResponseItem::Error::UNDEFINED_ERROR;
  $l_errorMessage = $LJ::Opensocial::ResponseItem::Error::UNAUTHORIZED
    if $l_errorCode == 101;
  $l_errorMessage = $LJ::Opensocial::ResponseItem::Error::BAD_REQUEST
    if $l_errorCode == 100;
  return "ERROR: $l_errorMessage";
}

#####

sub getArguments {
  my ($l_self,@l_args) = @_;
  my %l_outHash = ();
  foreach my $l_tag (@l_args) {
    $l_outHash{$l_tag} = $l_self->{uc $l_tag}
      if defined $l_self->{uc $l_tag};
  }
  return \%l_outHash;
}
 
##### Method implementations follow...

sub sendmessage {
  my ($l_self,$l_to,$l_subject,$l_body) = @_;
  $l_self->setSubject($l_subject);
  #$l_self->setBody($l_body);
  $l_self->setTo($l_to);

  my $l_args = 
    $l_self->getArguments((qw{username password subject body to ver}));

  return $l_self->call('LJ.XMLRPC.sendmessage',$l_args);
}

#####

sub DESTROY {
}

#####

1;

# End of file.
