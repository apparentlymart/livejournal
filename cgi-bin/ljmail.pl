#!/usr/bin/perl
#

use strict;
use MIME::Lite ();
use Text::Wrap ();

package LJ;

# determine how we're going to send mail
$LJ::OPTMOD_NETSMTP = eval "use Net::SMTP (); 1;";

if ($LJ::SMTP_SERVER) {
    die "Net::SMTP not installed\n" unless $LJ::OPTMOD_NETSMTP;
    MIME::Lite->send('smtp', $LJ::SMTP_SERVER, Timeout => 10);
} else {
    MIME::Lite->send('sendmail', $LJ::SENDMAIL);
}

# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.  Character set will only be used if message is not ascii.
# args: opt
# des-opt: Hashref of arguments.  <b>Required:</b> to, from, subject, body.
#          <b>Optional:</b> toname, fromname, cc, bcc, charset, wrap
# </LJFUNC>
sub send_mail
{
    my $opt = shift;

    my $msg = $opt;

    # did they pass a MIME::Lite object already?
    unless (ref $msg eq 'MIME::Lite') {

        my $clean_name = sub {
            my $name = shift;
            return "" unless $name;
            $name =~ s/[\n\t\(\)]//g;
            return $name ? " ($name)" : "";
        };

        my $body = $opt->{'wrap'} ? Text::Wrap::wrap('','',$opt->{'body'}) : $opt->{'body'};
        $msg = new MIME::Lite ('From' => "$opt->{'from'}" . $clean_name->($opt->{'fromname'}),
                                  'To' => "$opt->{'to'}" . $clean_name->($opt->{'toname'}),
                                  'Cc' => $opt->{'cc'},
                                  'Bcc' => $opt->{'bcc'},
                                  'Subject' => $opt->{'subject'},
                                  'Data' => $body);

        if ($opt->{'charset'} && ! (LJ::is_ascii($opt->{'body'}) && LJ::is_ascii($opt->{'subject'}))) {
            $msg->attr("content-type.charset" => $opt->{'charset'});
        }

        if ($opt->{'headers'}) {
            $msg->add(%{$opt->{'headers'}});
        }
    }

    # if send operation fails, buffer and send later
    my $buffer = sub {

        my $tries = 0;

        # aim to try 10 times, but that's redundant if there are fewer clusters
        my $maxtries = @LJ::CLUSTERS;
        $maxtries = 10 if $maxtries > 10;

        # select a random cluster master to insert to
        my $cid;
        while (! $cid && $tries < $maxtries) {
            my $idx = int(rand() * @LJ::CLUSTERS);
            $cid = $LJ::CLUSTERS[$idx];
            $tries++;
        }
        return undef unless $cid;

        # try sending later
        LJ::cmd_buffer_add($cid, 0, 'send_mail', Storable::freeze($msg));
    };

    my $rv = eval { $msg->send && 1; };
    return 1 if $rv;
    return 0 if $@ =~ /no data in this part/;  # encoding conversion error higher
    return $buffer->($msg);

}



1;


