#!/usr/bin/perl
#

use strict;

use lib "$ENV{LJHOME}/cgi-bin";
require "ljlib.pl";

package LJ;

use Text::Wrap ();
use Time::HiRes qw//;

use Encode qw//;
use MIME::Base64 qw//;
use LJ::DoSendEmail;

use Class::Autouse qw(
                      IO::Socket::INET
                      MIME::Lite
                      Mail::Address
                      );

my $done_init = 0;
sub init {
    return if $done_init++;
    if ($LJ::SMTP_SERVER) {
        # determine how we're going to send mail
        $LJ::OPTMOD_NETSMTP = eval "use Net::SMTP (); 1;";
        die "Net::SMTP not installed\n" unless $LJ::OPTMOD_NETSMTP;
        MIME::Lite->send('smtp', $LJ::SMTP_SERVER, Timeout => 10);
    } else {
        MIME::Lite->send('sendmail', $LJ::SENDMAIL);
    }
}

use MIME::Words qw//;

# <LJFUNC>
# name: LJ::send_mail
# des: Sends email.  Character set will only be used if message is not ASCII.
# args: opt, async_caller
# des-opt: Hashref of arguments.  Required: to, from, subject, body.
#          Optional: toname, fromname, cc, bcc, charset, wrap, html.
#          All text must be in UTF-8 (without UTF flag, as usual in LJ code).
#          Body and subject are converted to recipient-user mail encoding.
#          Subject line is encoded according to RFC 2047.
#          Warning: opt can be a MIME::Lite ref instead, in which
#          case it is sent as-is.
#          Raw mode: if hashref contains key 'raw_data', it considered as 
#          full text of e-mail message (including headers) and is sent as-is.
#          
# </LJFUNC>
sub send_mail
{
    my $opt = shift;
    my $async_caller = shift;

    init();

    my ($message_text, $from, @rcpts);
    my ($log_subject, $log_action);
    
    if (ref $opt eq 'MIME::Lite') {
        # did they pass a MIME::Lite object already?
        $message_text = $opt->as_string;
        $from = (map { $_->address } Mail::Address->parse($opt->get('From')))[0];
        foreach my $field (map { $opt->get($_) } qw(To Cc Bcc)) {
            next unless $field;
            push @rcpts, map { $_->address } Mail::Address->parse($field);
        }
        $log_subject = $opt->get('Subject');
        $log_action = 'email_send_mimelite';
    } elsif ($opt->{raw_data}) {
        $message_text = $opt->{raw_data};
        $from = (map { $_->address } Mail::Address->parse($opt->{from}))[0];
        foreach my $field (map { $opt->{$_} } qw(to tc bcc)) {
            next unless $field;
            push @rcpts, map { $_->address } Mail::Address->parse($field);
        }
        $log_subject = "Unknown (raw message)";
        $log_action = 'email_send_raw';
    } else {
        my $clean_name = sub {
            my ($name, $email) = @_;
            return $email unless $name;
            $name =~ s/[\n\t\"<>]//g;
            return $name ? "\"$name\" <$email>" : $email;
        };

        $Text::Wrap::huge = 'overflow'; # Don't break long lines with urls.
        my $body = $opt->{'wrap'} ? Encode::encode_utf8(Text::Wrap::wrap('','',Encode::decode_utf8($opt->{'body'}))) : $opt->{'body'};
        my $subject = $opt->{'subject'};
        my $fromname = $opt->{'fromname'};

        # if it's not ascii, add a charset header to either what we were explictly told
        # it is (for instance, if the caller transcoded it), or else we assume it's utf-8.
        # Note: explicit us-ascii default charset suggested by RFC2854 sec 6.
        $opt->{'charset'} ||= "utf-8";
        my $charset;
        if (!LJ::is_ascii($subject)
         || !LJ::is_ascii($body)
         || ($opt->{html} && !LJ::is_ascii($opt->{html}))
         || !LJ::is_ascii($fromname)) {
            $charset = $opt->{'charset'};
        } else {
            $charset = 'us-ascii';
        }

        # Don't convert from us-ascii and utf-8 charsets.
        unless (($charset =~ m/us-ascii/i) || ($charset =~ m/^utf-8$/i)) {
            Encode::from_to($body,              "utf-8", $charset);
            # Convert also html-part if we has it.
            if ($opt->{html}) {
                Encode::from_to($opt->{html},   "utf-8", $charset);
            }
        }

        Encode::from_to($subject, "utf-8", $charset) unless $charset =~ m/^utf-8$/i;
        if (!LJ::is_ascii($subject)) {
            $subject = MIME::Words::encode_mimeword($subject, 'B', $charset);
        }

        Encode::from_to($fromname, "utf-8", $charset) unless $charset =~ m/^utf-8$/i;
        if (!LJ::is_ascii($fromname)) {
            $fromname = MIME::Words::encode_mimeword($fromname, 'B', $charset);
        }
        $fromname = $clean_name->($fromname, $opt->{'from'});

        my $msg;
        if ($opt->{html}) {
            # do multipart, with plain and HTML parts

            $msg = new MIME::Lite ('From'    => $fromname,
                                   'To'      => $clean_name->($opt->{'toname'},   $opt->{'to'}),
                                   'Cc'      => $opt->{'cc'},
                                   'Bcc'     => $opt->{'bcc'},
                                   'Subject' => $subject,
                                   'Type'    => 'multipart/alternative');

            # add the plaintext version
            my $plain = $msg->attach(
                                     'Type'     => 'text/plain',
                                     'Data'     => "$body\n",
                                     'Encoding' => 'quoted-printable',
                                     );
            $plain->attr("content-type.charset" => $charset);

            # add the html version
            my $html = $msg->attach(
                                    'Type'     => 'text/html',
                                    'Data'     => $opt->{html},
                                    'Encoding' => 'quoted-printable',
                                    );
            $html->attr("content-type.charset" => $charset);

        } else {
            # no html version, do simple email
            $msg = new MIME::Lite ('From'    => $fromname,
                                   'To'      => $clean_name->($opt->{'toname'},   $opt->{'to'}),
                                   'Cc'      => $opt->{'cc'},
                                   'Bcc'     => $opt->{'bcc'},
                                   'Subject' => $subject,
                                   'Type'    => 'text/plain',
                                   'Data'    => $body);

            $msg->attr("content-type.charset" => $charset);
        }

        if ($opt->{headers}) {
            while (my ($tag, $value) = each %{$opt->{headers}}) {
                $msg->add($tag, $value);
            }
        }
        
        $message_text = $msg->as_string;
        $from = (map { $_->address } Mail::Address->parse($msg->get("From")))[0];
        foreach my $field (map { $msg->get($_) } qw(To Cc Bcc)) {
            next unless $field;
            push @rcpts, map { $_->address } Mail::Address->parse($field);
        }
        $log_subject = $msg->get('Subject');
        $log_action = ($opt->{html}) ? 'email_send_html' : 'email_send_text';
    }

    LJ::note_recent_action(undef, $log_action);


    ## Start sending process:
    ##  1. At stage One we try to send email right now from this process 
    ##  2. If stage one faults for some reason, at stage Two add task to TheSchwartz queue.
    ##

    ## Stage 1.
    ##  We never should send emails online when user waits for response.
    ##  Workers send emails too and exactly in this case 
    ##  we spend worker's time to try to send email directly from this process.
    ##  This approach intended to reduce TheSchwartz workload.
    unless (LJ::is_web_context()){
        foreach my $rcpt (@rcpts){
            my $res = LJ::DoSendEmail->send($rcpt, {
                        from    => $from,         ## Envelope From
                        data    => $message_text,

                        ## Optional params
                        # sender_id => "",  ## stored in email headers. for debug.
                        # timeout   => 300, ## Default timeout for sending email is 300 sec.
                        });
            ## handle result
            if ($res eq LJ::DoSendEmail::OK){
            ## email succeffully sent
                $rcpt = ""; # forget about this rcpt
            } else {
            ## handle error 

                ## 5xx errors
                my $details = LJ::DoSendEmail->details;
                LJ::errobj('DieString', message => "send_email to $rcpt failed: $details")->log
                    if LJ::DoSendEmail->status eq 5;
            }

        }

        ## empty rcpt means that email was successfully sent
        @rcpts = grep {$_} @rcpts;
    }

    ## Do we still have someone to notify?
    return 1 unless @rcpts; 

    ## Stage 2.
    ##  Ok. We've tried to avoid this... But delayed sending.
    ##  Deligate this job to SendMail worker.
     
    my $starttime = [Time::HiRes::gettimeofday()];

    ## '_reuse_any_existing_connection' will return 'mass' schwartz handle 
    ## when called from 'mass' workers and will return 'default' for the rest.
    my $sclient = LJ::theschwartz({ 'role' => $opt->{'_schwartz_role'} }) 
        or die "Misconfiguration in mail.  Can't go into TheSchwartz.";

    ## coalesce param.
    my $coalesce = '';
    if (@rcpts == 1) {
        $rcpts[0] =~ /(.+)@(.+)$/;
        $coalesce = lc($2) . '@' . lc($1);   # we store it reversed in database
    }

    my $job = TheSchwartz::Job->new(funcname => "TheSchwartz::Worker::SendEmail",
                                    arg      => {
                                        env_from => $from,
                                        rcpts    => \@rcpts,
                                        data     => $message_text,
                                    },
                                    coalesce => $coalesce,
                                    );
    my $h = $sclient->insert($job);

    LJ::blocking_report( 'the_schwartz', 'send_mail',
                         Time::HiRes::tv_interval($starttime));
    return $h ? 1 : 0;

}

1;
