# LJ/Opensocial/Message.pm - jop

package LJ::Opensocial::Message;
use LJ::Opensocial::Util::Object;
use LJ::Opensocial::Util::XMLRPC;

our @ISA = (LJ::Opensocial::Util::Object);
use strict;

#####

sub new {
  my ($l_class,$l_body,$l_params) = @_;
  my $l_ref = {};
  bless $l_ref,$l_class;
  $l_ref->{BODY} = $l_body;
  foreach my $l_tag (keys %{$l_params}) {
    $l_ref->{LJ::Opensocial::Message::Field::lookup($l_tag)} 
      = $$l_params{$l_tag};
  }
  return $l_ref;
}

#####

sub send {
  my ($l_self,$l_recipients) = @_;

  my $l_responseItem = LJ::Opensocial::ResponseItem::new();

  # hook up XML::RPC here
  my $l_osServer = LJ::Opensocial::Util::XMLRPC->new();

  # extract to cfg somewhere ## TODO
  $l_osServer->setUrl('http://www.livejournal.com/interface/xmlrpc');
  $l_osServer->setDebug(1);
  $l_osServer->setVer(1);

  # extract to auth somewhere ## TODO
  $l_osServer->setUsername('james');
  $l_osServer->setPassword('norfleet1');

  my $l_result = 
    $l_osServer->sendmessage($$l_recipients,$l_self->{TITLE},$l_self->{BODY});
  if ($l_result =~ /^ERROR\:\s(.*)$/) {
    $l_responseItem->setError($1);
  }

  # switch view to $l_destination (## TODO), then...
  return $l_responseItem; 
}

#####

1;

# End of file.
