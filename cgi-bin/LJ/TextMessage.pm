#!/usr/bin/perl
#
# LJ::TextMessage class
# See perldoc documentation at the end of this file.
#
# -------------------------------------------------------------------------
#
# This package is released under the LGPL (GNU Library General Public License)
#
# A copy of the license has been included with the software as LGPL.txt.  
# If not, the license is available at:
#      http://www.gnu.org/copyleft/library.txt
#
# -------------------------------------------------------------------------
#

package LJ::TextMessage;

use URI::Escape;
use LWP::UserAgent;

use strict;
use vars qw($VERSION $SENDMAIL %providers);

$VERSION = '1.4.5';

# default path to sendmail, if none other specified.  we should probably
# use something more perl-ish and less unix-specific, but whateva'

$SENDMAIL = "/usr/sbin/sendmail -t";   

%providers = (

    'email' => {
        'name'		=> 'Other',
        'notes'		=> 'If your provider isn\'t supported directly, enter the email address that sends you a text message in phone number field.  To be safe, the entire message is sent in the body of the message, and the length limit is really short.  We\'d prefer you give us information about your provider so we can support it directly.',
        'fromlimit'	=> 15,
        'msglimit'	=> 100,
        'totlimit'	=> 100,
    },

    'airtouch' => {
        'name'		=> 'Verizon Wireless (formerly Airtouch)',
        'notes'		=> '10-digit phone number.  Goes to @airtouchpaging.com.  This is ONLY for former Airtouch customers.  Normal Verizon Wireless customers should use the normal Verizon Wireless option.',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'ameritech' => {
        'name'		=> 'Ameritech (ACSWireless)',
        'notes'		=> '10-digit phone number.  Goes to number@paging.acswireless.com',
        'fromlimit'	=> 120,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'arch' => {
        'name'		=> 'Arch Wireless',
        'notes'		=> 'Enter your 10-digit phone number.  Sent via http://www.arch.com/message/ gateway.  Assumes blank PIN.',
        'fromlimit'	=> 15,
        'msglimit'	=> 220,
        'totlimit'	=> 220,
    },

    'att' => {
        'name'		=> 'AT&T Wireless',
        'notes'		=> '10-digit phone number.  Goes to @mobile.att.net',
        'fromlimit'	=> 50,
        'msglimit'	=> 150,
        'totlimit'	=> 150,
    },

    'bellmobilityca' => {
        'name'		=> 'Bell Mobility Canada',
        'notes'		=> '11-digit phone number (1 + area-code + phone-number).  Goes to @txt.bellmobility.ca',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'bellsouthmobility' => {
        'name'		=> 'BellSouth Mobility',
        'notes'		=> 'Enter your 10-digit phone number.  Goes to @blsdcs.net via email.',
        'fromlimit'	=> 15,
        'msglimit'	=> 160,
        'totlimit'	=> 160,
    },

    'btcellnet' => {
        'name'		=> 'BT Cellnet',
        'notes'		=> 'Input phone number - must be enabled first.  Goes to +44[number]@mmail.co.uk.',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'cellularonedobson' => {
        'name'		=> 'CellularOne (Dobson)',
        'notes'		=> 'Enter your 10 digit phone number.  Sent through email gateway @mobile.celloneusa.com.',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'cingular' => 
    {
        'name'		=> 'Cingular New England',
        'notes'		=> 'Enter 8 digit PIN or user name.  Goes to @sbcemail.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 160,
        'totlimit'	=> 160,
    },

    'cingular-acs' => {
        'name'		=> 'Cingular Wireless - digitaledge.acswireless.com',
        'notes'		=> '10-digit phone number.  Goes to 10digits@digitaledge.acswireless.com.',
        'fromlimit'	=> 30,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'cingular-texas' => 
    {
        'name'		=> 'Cingular Wireless - (Houston) Texas',
        'notes'		=> 'Enter phone number.  Goes to @mobile.mycingular.net',
        'fromlimit'	=> 20,
        'msglimit'	=> 150,
        'totlimit'	=> 150,
    },

    'fidoca' => {
        'name'		=> 'Fido Canada',
        'notes'		=> 'Enter your 10-digit phone number.  Message is sent via the email gateway, to 10digits@fido.ca.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,
    },

    'imcingular' => 
    {
        'name'		=> 'Cingular IM Plus/Bellsouth IPS',
        'notes'		=> 'Enter 8 digit PIN or user name.  Goes to @imcingular.com',
        'fromlimit'	=> 100,
        'msglimit'	=> 16000,
        'totlimit'	=> 16000,
    },

    'imcingular-cell' => 
    {
        'name'		=> 'Cingular IM Plus/Bellsouth IPS Cellphones',
        'notes'		=> 'Enter phone number.  Goes to @mobile.mycingular.com',
        'fromlimit'	=> 100,
        'msglimit'	=> 16000,
        'totlimit'	=> 16000,
    },

    'metrocall' => {
        'name'		=> 'Metrocall Pager',
        'notes'		=> '10-digit phone number.  Goes to number@page.metrocall.com',
        'fromlimit'	=> 120,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'movistar' => {
        'name'		=> 'Telefonica Movistar',
        'notes'		=> '10-digit phone number.  Goes to number@movistar.net',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'mtsmobility' => {
        'name'		=> 'Manitoba Telecom Systems',
        'notes'		=> '10-digit phone number.  Goes to @text.mtsmobility.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'nextel' => {
        'name'		=> 'Nextel',
        'notes'		=> '10-digit phone number.  Goes to 10digits@messaging.nextel.com.  Note: do not use dashes in your phone number.',
        'fromlimit'	=> 50,
        'msglimit'	=> 126,
        'totlimit'	=> 126,
    },

    'ntelos' => {
        'name'		=> 'NTELOS',
        'notes'		=> '10-digit phone number.  Goes to 10digits@pcs.ntelos.com.',
        'fromlimit'	=> 30,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'pacbell' => {
        'name'		=> 'Pacific Bell Cingular',
        'notes'		=> '10-digit phone number.  Goes to @mobile.mycingular.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'pagenet' => {
        'name'		=> 'Pagenet',
        'notes'		=> '10-digit phone number (or gateway and pager number separated by a period).  Goes to number@pagenet.net.',
        'fromlimit'	=> 20,
        'msglimit'	=> 220,
        'totlimit'	=> 240,
    },

    'pcsrogers' => {
        'name'		=> 'PCS Rogers AT&T Wireless',
        'notes'		=> '10-digit phone number.  Goes to number@pcs.rogers.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 150,
        'totlimit'	=> 150,
    },

    'ptel' => {
        'name'		=> 'Powertel',
        'notes'		=> '10-digit phone number.  Goes to number@ptel.net',
        'fromlimit'	=> 20,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'qwest' => {
        'name'		=> 'Qwest',
        'notes'		=> '10-digit phone number.  Goes to @uswestdatamail.com',
        'fromlimit'	=> 14,
        'msglimit'	=> 100,
        'totlimit'	=> 100,
    },

    'skytelalpha' => {
        'name'		=> 'Skytel - Alphanumeric',
        'notes'		=> 'Enter your 7-digit pin number as your number and your message will be mailed to pin@skytel.com',
        'fromlimit'	=> 15,
        'msglimit'	=> 240,
        'totlimit'	=> 240,
    },

    'sprintpcs' => {
        'name'		=> 'Sprint PCS',
        'notes'		=> 'Enter your 10-digit phone number.  Goes to @messaging.sprintpcs.com',
        'fromlimit'	=> 15,
        'msglimit'	=> 97,
        'totlimit'	=> 97,
    },

    'telus' => {
        'name'		=> 'Telus Mobility',
        'notes'		=> '10-digit phone number.  Goes to 10digits@msg.telus.com.',
        'fromlimit'	=> 30,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },

    'uboot' => {
        'name'		=> 'uBoot',
        'notes'		=> 'Enter your username as the phone number.  See http://www.uboot.com for more details',
        'fromlimit'	=> 146,
        'msglimit'	=> 146,
        'totlimit'	=> 146,
    },

    'vzw' => {
        'name'		=> 'Verizon Wireless',
        'notes'		=> 'Enter your 10-digit phone number.  Messages are sent via email to number@vtext.com.',
        'fromlimit'	=> 34,
        'msglimit'	=> 140,
        'totlimit'	=> 140,	      
    },

    'voicestream' => {
        'name'		=> 'Voicestream',
        'notes'		=> 'Enter your 10-digit phone number.  Message is sent via the web gateway on Voicestream.com which is often a lot faster than the email gateway.  Expect arrival within 5 or 6 seconds.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,
    },

    'voicestream2' => {
        'name'		=> 'Voicestream',
        'notes'		=> 'Enter your 10-digit phone number.  Message is sent via the email gateway, since they changed their web gateway and we have not gotten it working with the new one yet.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,
    },

    'wyndtell' => 
    {
        'name'		=> 'WyndTell',
        'notes'		=> 'Enter username/phone number.  Goes to @wyndtell.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 480,
        'totlimit'	=> 500,
    },

);

sub providers
{
    return sort { lc($providers{$a}->{'name'}) cmp lc($providers{$b}->{'name'}) } keys %providers;    
}

sub provider_info
{
    my $provider = shift;
    return { %{$providers{$provider}} };
}

sub new {
    my ($class, $args) = @_;
    my $self = {};
    bless $self, ref $class || $class;
    
    $self->init($args);
    return $self;
}

sub init {
    my $self = shift;
    my $args = shift;
    $self->{'sendmail'} = $args->{'mailcommand'} || $SENDMAIL;
    $self->{'provider'} = $args->{'provider'};
    $self->{'number'} = $args->{'number'};
}
 
sub send
{
    my $self = shift;
    my $msg = shift;      # hashref: 'from', 'message'
    my $errors = shift;   # arrayref
    my $provider = $self->{'provider'};

    unless ($provider) {
        push @$errors, "No provider specified in object constructor.";
        return;
    }

    my $prov = $providers{$provider};

    ##
    ## truncate 'from' if it's too long for the given provider
    ##

    if (length($msg->{'from'}) > $prov->{'fromlimit'}) {
        $msg->{'from'} = substr($msg->{'from'}, 0, $prov->{'fromlimit'});
    }

    ##
    ## now send the message, based on the provider
    ##

    if ($provider eq "email") 
    {
        send_mail($self, {
            'to'	=> $self->{'number'},
            'from'	=> "LiveJournal",
            'body'	=> "(f:$msg->{'from'})$msg->{'message'}",
        });
    } 

    elsif ($provider eq "airtouch")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@sender.airtouchpaging.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "ameritech")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@paging.acswireless.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "arch")
    {
        post_webform("http://www.arch.com/cgi-bin/archepage.exe", $errors, {
            "ACCESS"	=> $self->{'number'},
            "MSSG"	=> "($msg->{'from'}) $msg->{'message'}",
            "Q1"	=> "1",
            "PIN"	=> "",
        });
    }

    elsif ($provider eq "att")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@mobile.att.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "bellmobilityca")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@txt.bellmobility.ca",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "bellsouthmobility")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@blsdcs.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "btcellnet")
    {
        send_mail($self, { 
            'to'	=> "+44".$self->{'number'}."\@mmail.co.uk",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "cellularonedobson")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@mobile.celloneusa.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "cingular")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@sbcemail.com",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "cingular-acs")  # Cingular Wireless - digitaledge acswireless
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@digitaledge.acswireless.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "cingular-texas")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@mobile.mycingular.net",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "fidoca" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@fido.ca",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "imcingular")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@imcingular.com",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "imcingular-cell")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@mobile.mycingular.com",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "metrocall")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@page.metrocall.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "movistar")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@correo.movistar.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "mtsmobility")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@text.mtsmobility.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "nextel")  # Nextel
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@messaging.nextel.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "ntelos")  # NTELOS PCS
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@pcs.ntelos.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "pacbell")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@mobile.mycingular.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "pagenet")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@pagenet.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "pcsrogers")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@pcs.rogers.com",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
	    'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "ptel")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@ptel.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }

    elsif ($provider eq "qwest")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@uswestdatamail.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "skytelalpha")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@skytel.com",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "sprintpcs") # SprintPCS
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@messaging.sprintpcs.com",
            'from'      => "$msg->{'from'}\@livejournal.com",
            'body'      => "$msg->{'message'}",
	    'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "telus")  # Telus Mobility
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@msg.telus.com",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "uboot")
    {
       	post_webform("http://www.uboot.com/cgi-bin/nickpage.fcgi", $errors, {
            "page"	=> "Sms",
            "action"	=> "send_sms",
            "nickname"	=> $self->{'number'},
            "text"	=> "LiveJournal($msg->{'from'}) $msg->{'message'}",
        });
    }

    elsif ($provider eq "vzw")  # Verizon Wireless
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vtext.com",
            'from'      => "$msg->{'from'}\@livejournal.com",
            'body'      => "$msg->{'message'}",
	    'subject'	=> "LJ",
        });
    }

    elsif ($provider eq "voicestream" )
    {
        post_webform("http://www.voicestream.com/messagecenter/".
                     "default.asp?num=$self->{'number'}", $errors, {
            "txtNum"		=> $self->{'number'},
            "txtFrom"		=> $msg->{'from'},
            "txtMessage"	=> $msg->{'message'},
        });
    }

    elsif ($provider eq "voicestream2" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@voicestream.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "wyndtell")
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@wyndtell.com",
            'from'	=> $msg->{'from'},
            'body'	=> $msg->{'message'},
        });
    }

    else {
        push @$errors, "Tried to send a message to an unknown or unsupported provider.";
    }
}

sub post_webform
{
    my ($url, $errors, $postvars) = @_;

    ### we're going to POST to provider's page
    my $ua = new LWP::UserAgent;
    $ua->agent("Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)");
    $ua->timeout(5);

    my $req = new HTTP::Request POST => $url;
    $req->content_type('application/x-www-form-urlencoded');
    $req->content(request_string($postvars));

    # Pass request to the user agent and get a response back
    my $res = $ua->request($req);
    if ($res->is_success) {
        return;
    } else {
        push @$errors, "There was some error contacting the user's text messaging service via its web gateway.  The message was most likely not sent.";
        return;
    }
}

sub send_emailgate
{
    my ($self, $msg, $domain) = @_;

    send_mail($self, {
        'to'		=> "$self->{'number'}\@$domain",
        'from'		=> "webmaster\@livejournal.com ($msg->{'from'})",
        'subject'	=> "LJ Msg",
        'body'		=> $msg->{'message'},
    });
}

sub send_mail
{
    my $self = shift;
    my $opt = shift;
    open (MAIL, "|" . $self->{'sendmail'});
    print MAIL "To: $opt->{'to'}\n";
    print MAIL "Bcc: $opt->{'bcc'}\n" if ($opt->{'bcc'});
    print MAIL "From: $opt->{'from'}";
    if ($opt->{'fromname'}) {
        print MAIL " ($opt->{'fromname'})";
    }
    print MAIL "\nSubject: $opt->{'subject'}\n\n";
    print MAIL $opt->{'body'};
    close MAIL;
}

sub request_string
{
    my ($vars) = shift;
    my $req = "";
    foreach (sort keys %{$vars})
    {
        my $val = uri_escape($vars->{$_},"\+\=\&");
        $val =~ s/ /+/g;
        $req .= "&" if $req;
        $req .= "$_=$val";
    }
    return $req;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

LJ::TextMessage - text message phones/pages using a variety of methods/services

=head1 SYNOPSIS

  use LJ::TextMessage;

  @providers = LJ::TextMessage::providers();
  foreach my $p (@providers) {
      my $info = LJ::TextMessage::provider_info($p);
      print "Name: $info->{'name'}\n";
      print "Notes: $info->{'notes'}\n";
      print "Limits: \n";
      foreach my $limit (qw(from msg tot)) {
	  print "  $limit: ", $info->{"${limit}limit"}, "\n";
      }
  }

  my $phone = new LJ::TextMessage { 
      'provider' => 'voicestream',
      'number' => '2045551212',
      'mailcommand' => '/usr/local/sbin/sendmail -t',
  };

  my @errors;
  $phone->send({ 'from' => 'Bob', 
		 'message' => "Hello!  This is my message!" },
	       \@errors);
  if (@errors) {
      ...
  } else {
      print "Message sent!\n";
  }

=head1 DESCRIPTION

The synopsis pretty much shows all the functionality that's available,
but details would be nice here.

=head1 BUGS

This library is highly volatile, as cellphone and pager providers can 
change the details of their web or email gateways at any time.  In 
practice I haven't had to update this library much, but providers have 
no responsibility to tell me when they change their form field names
on their website, or change URLs*.

This documentation sucks rancid goats**.


*  - This will, of course, change once LJ has conquered the world.
** - No, not Frank.

=head1 AUTHOR

Written by:
  Nicholas Tang (ntang@livejournal.com)

and members of the LJ Textmessage community:
  - l2g
  - delphy
  - rory
  - tsutton
(if you've been forgotten, please give a holler!)

Based on (mostly still, actually) code by:
  Brad Fitzpatrick, bradfitz@bradfitz.com

Information about text messaging gateways from many.

=cut
