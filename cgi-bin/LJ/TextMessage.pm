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
use MIME::Lite;

use strict;
use vars qw($VERSION $SENDMAIL %providers);

$VERSION = '1.4.10';

# default path to sendmail, if none other specified.  we should probably
# use something more perl-ish and less unix-specific, but whateva'

$SENDMAIL = "/usr/sbin/sendmail -t";   

%providers = (

    'email' => {
        'name'       => 'Other',
        'notes'      => 'If your provider isn\'t supported directly, enter the email address that sends you a text message in phone number field.  To be safe, the entire message is sent in the body of the message, and the length limit is really short.  We\'d prefer you give us information about your provider so we can support it directly.',
        'fromlimit'  => 15,
        'msglimit'   => 100,
        'totlimit'   => 100,
    },

    'airtouch' => {
        'name'       => 'Verizon Wireless (formerly Airtouch)',
        'notes'      => 'Enter your 10 digit phone number. Messages are sent to number@airtouchpaging.com. This is ONLY for former AirTouch customers. Verizon Wireless customers should use Verizon Wireless, instead.',
        'fromlimit'  => 20,
        'msglimit'   => 120,
        'totlimit'   => 120,
    },

    'alltel' => {
        'name'          => 'Alltel',
        'notes'         => '10-digit phone number.  Goes to @message.alltel.com, not Alltel web text messaging gateway.',
        'fromlimit'     => 50,
        'msglimit'      => 116,
        'totlimit'      => 116,
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
        'msglimit'	=> 240,
        'totlimit'	=> 240,
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

    'beemail' => {
        'name'		=> 'BeeLine GSM',
        'notes'		=> 'Sent by addressing the message to number@sms.beemail.ru',
        'fromlimit'	=> 50,
        'msglimit'	=> 255,
        'totlimit'	=> 255,
    },

    'bellsouthmobility' => {
        'name'		=> 'BellSouth Mobility',
        'notes'		=> 'Enter your 10-digit phone number.  Goes to @blsdcs.net via email.',
        'fromlimit'	=> 15,
        'msglimit'	=> 160,
        'totlimit'	=> 160,
    },

    'blueskyfrog' => {
        'name'		=> 'Blue Sky Frog',
        'notes'		=> 'Sent by addressing the message to number@blueskyfrog.com',
        'fromlimit'	=> 30,
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

    'centennial' => {
        'name'		=> 'Centennial Wireless',
        'notes'		=> 'Sent through web form at http://www.centennialcom.com',
        'fromlimit'	=> 10,
        'msglimit'	=> 110,
        'totlimit'	=> 110,
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

    'cricket' => {
        'name'		=> 'Cricket',
        'notes'		=> 'Enter your 10-digit phone number.  Messages are sent via Cricket\'s web gateway.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,	      
    },

    'csouth1' => {
        'name'		=> 'Cellular South',
        'notes'		=> 'Enter your 10-digit phone number.  Messages are sent to number@csouth1.com',
        'fromlimit'	=> 50,
        'msglimit'	=> 155,
        'totlimit'	=> 155,	      
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

    'kyivstar' => {
        'name'		=> 'Kyivstar',
        'notes'		=> 'Sent by addressing the message to number@sms.kyivstar.net',
        'fromlimit'	=> 30,
        'msglimit'	=> 160,
        'totlimit'	=> 160,
    },

    'lmt' => {
        'name'		=> 'LMT',
        'notes'		=> 'Sent by addressing the message to number@smsmail.lmt.lv',
        'fromlimit'	=> 30,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
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

    'o2' => {
        'name'          => 'O2 (formerly BTCellnet)',
        'notes'         => 'Enter O2 username - must be enabled first at http://www.o2.co.uk. Goes to username@o2.co.uk.',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
    },

    'o2mmail' => {
        'name'          => 'O2 M-mail (formerly BTCellnet)',
        'notes'         => 'Enter phone number, omitting intial zero - must be enabled first by sending an SMS saying "ON" to phone number "212".  Goes to +44[number]@mmail.co.uk.',
        'fromlimit'     => 20,
        'msglimit'      => 120,
        'totlimit'      => 120,
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

    'suncom' => {
        'name'          => 'SunCom',
        'notes'         => 'Enter your number. Email will be sent to number@tms.suncom.com.',
        'fromlimit'     => 18,
        'msglimit'      => 110,
        'totlimit'      => 110,
    },


    'telus' => {
        'name'		=> 'Telus Mobility',
        'notes'		=> '10-digit phone number.  Goes to 10digits@msg.telus.com.',
        'fromlimit'	=> 30,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },
    

    'tmobileaustria' => {
        'name'       => 'T-Mobile Austria',
        'notes'      => 'Enter your number starting with 43676. Email will be sent to number@sms.t-mobile.at.',
        'fromlimit'  => 15,
        'msglimit'   => 160,
        'totlimit'   => 160,
    },

    'tmobilegermany' => {
        'name'       => 'T-Mobile Germany',
        'notes'      => 'Enter your number. Email will be sent to number@T-D1-SMS.de',
        'fromlimit'  => 15,
        'msglimit'   => 160,
        'totlimit'   => 160,
    },

    'tmobileholland' => {
        'name'       => 'T-Mobile Netherlands',
        'notes'      => 'Send "EMAIL ON" to 555 from your phone, then enter your number starting with 316. Email will be sent to number@gin.nl',
        'fromlimit'  => 15,
        'msglimit'   => 160,
        'totlimit'   => 160,
    },

    'tmobileusa' => {
        'name'		=> 'T-Mobile',
        'notes'		=> 'Messages are sent to number@tmomail.net',
        'fromlimit'	=> 30,
        'msglimit'	=> 160,
        'totlimit'	=> 160,	      
    },

    'uboot' => {
        'name'		=> 'uBoot',
        'notes'		=> 'Enter your username as the phone number.  See http://www.uboot.com for more details',
        'fromlimit'	=> 146,
        'msglimit'	=> 146,
        'totlimit'	=> 146,
    },
    
    'umc' => {
        'name'		=> 'UMC',
        'notes'		=> 'Sent by addressing the message to number@sms.umc.com.ua',
        'fromlimit'	=> 10,
        'msglimit'	=> 120,
        'totlimit'	=> 120,
    },    

    'uscc' => {
        'name'		=> 'US Cellular',
        'notes'		=> 'Enter a 10 digit USCC Phone Number. Messages are sent via http://uscc.textmsg.com/scripts/send.idc and only contain the message field',
        'msglimit'	=> 150,
        'totlimit'	=> 150,	      
    },

    'vzw' => {
        'name'		=> 'Verizon Wireless',
        'notes'		=> 'Enter your 10-digit phone number.  Messages are sent via email to number@vtext.com.',
        'fromlimit'	=> 34,
        'msglimit'	=> 140,
        'totlimit'	=> 140,	      
    },

    'vodacom' => {
        'name'		=> 'Vodacom',
        'notes'		=> 'Enter your 10 digit phone number. Messages are sent via Vodacom\'s web gateway.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,
    },

    'voicestream' => {
        'name'		=> 'Voicestream',
        'notes'		=> 'Enter your 10-digit phone number.  Message is sent via the email gateway, since they changed their web gateway and we have not gotten it working with the new one yet.',
        'fromlimit'	=> 15,
        'msglimit'	=> 140,
        'totlimit'	=> 140,
    },
    
    'vtext' => {
        'name'		=> 'Vtext (Verizon)',
        'notes'		=> 'Message is sent via the email gateway @ vtext.com',
        'fromlimit'	=> 20,
        'msglimit'	=> 150,
        'totlimit'	=> 150,
    },

    'wyndtell' => {
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
    my $provider = remap(shift);
    return { %{$providers{$provider}} };
}

sub remap {
    my $provider = shift;
    return "o2mmail" if $provider eq "btcellnet";
    return "voicestream" if $provider eq "voicestream2";
    return "tmobileusa" if $provider eq "tmomail";
    return "suncom" if $provider eq "tms-suncom";
    return $provider;
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
    $self->{'provider'} = remap($args->{'provider'});
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

    elsif ($provider eq "alltel")
    {
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@message.alltel.com",
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
        send_mail($self, { 
            'to'	=> "$self->{'number'}\@archwireless.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
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

    elsif ($provider eq "beemail") 
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}@\sms.beemail.ru",
            'body'	=> "$msg->{'from'} - $msg->{'message'}",
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

   
    elsif ($provider eq "blueskyfrog") 
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}\@blueskyfrog.com",
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

    elsif ($provider eq "centennial")
    {
        post_webform("http://matrix.wysdom.com/cgi-bin/mim/newxmessage.cgi", $errors, {
            'ToNumber'	 => $self->{'number'},
            'Message'	 => $msg->{'message'},
	    'FromNumber' => $msg->{'from'},
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

    elsif ($provider eq "cingular-acs")
    {
	send_mail($self, {
            'to'        => "$self>{'number'}\@digitaledge.acswireless.com",
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

    elsif ($provider eq "cricket") {
        post_webform("http://www.cricketcommunications.com/text/sendto_sms_system.asp", $errors, {
            "Cricket_Phone_Number" => $self->{'number'},
            "msg"                  => $msg->{'message'},
        });
    }

    elsif ($provider eq "csouth1") {
        send_mail($self, {
            'to' => "$self->{'number'}\@csouth1.com",
            'from' => $msg->{'from'},
            'body' => $msg->{'message'},
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
    
    elsif ($provider eq "kyivstar") 
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}@\sms.kyivstar.net",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    } 

    elsif ($provider eq "lmt") 
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}@\smsmail.lmt.lv",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
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

    elsif ($provider eq "o2")
    {
        send_mail($self, {
            'to'        => $self->{'number'}."\@o2.co.uk",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "o2mmail")
    {
        send_mail($self, {
            'to'        => "+44".$self->{'number'}."\@mmail.co.uk",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
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
            # 'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'from'}: $msg->{'message'}",
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

    elsif ($provider eq "suncom") {
        send_mail($self, {
            'to'   => "$self->{'number'}\@tms.suncom.com",
            'from' => "$msg->{'from'}",
            'body' => "$msg->{'message'}",
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

    elsif ($provider eq "tmobileaustria")    
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@sms.t-mobile.at",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "tmobilegermany")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@T-D1-SMS.de",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "tmobileholland")
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@gin.nl",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }

    elsif ($provider eq "tmobileusa") 
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@tmomail.net",
            'subject'   => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
            'from'      => "LJ",
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
    
    elsif ($provider eq "uma") 
    {
        send_mail($self, {
            'to'	=> "$self->{'number'}@\sms.umc.com.ua",
            'from'	=> "$msg->{'from'}",
            'body'	=> "$msg->{'message'}",
        });
    }    

    elsif ($provider eq "uscc")  # U.S Cellular
    {
        post_webform("http://uscc.textmsg.com/scripts/send.idc", $errors, { 
            "number"		=> $self->{'number'},
            "message"		=> $msg->{'message'},
        });
    }

    elsif ($provider eq "vzw")  # Verizon Wireless
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vtext.com",
            'from'      => "$msg->{'from'}\@livejournal.com",
            'body'      => "$msg->{'message'}",
	    'subject'	=> "LJ",

            # is this necessary?  (--brad 1.4.10)
            #'return-path'    => "$msg->{'from'}\@livejournal.com",
        });
    }

    elsif ($provider eq "vodacom" )
    {
        post_webform("http://websms.vodacom.net/send.php3", $errors, {
            "cellnum"         => $self->{'number'},
            "message"         => $msg->{'message'},
        });
    }

    elsif ($provider eq "voicestream" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@voicestream.net",
            'from'      => "$msg->{'from'}",
            'body'      => "$msg->{'message'}",
        });
    }
    
    elsif ($provider eq "vtext" )
    {
        send_mail($self, {
            'to'        => "$self->{'number'}\@vtext.com",
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
    if ($res->is_success || $res->is_redirect) {
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

    my $msg =  new MIME::Lite ('From' => $opt->{'from'},
                               'To' => $opt->{'to'},
                               'Subject' => $opt->{'subject'},
                               'Data' => $opt->{'body'});
    if ($self->{'smtp'}) {
        return $msg->send_by_smtp($self->{'smtp'}, Timeout => 10);
    }

    return $msg->send_by_sendmail($self->{'sendmail'});
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
  - cbartow
  - 22dip
  - halkeye
  - idigital
(if you've been forgotten, please give a holler!)

Based on (mostly still, actually) code by:
  Brad Fitzpatrick, bradfitz@bradfitz.com

Information about text messaging gateways from many.

=cut
