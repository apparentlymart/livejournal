#!/usr/bin/perl

package LJ::Emailpost;
use strict;
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljprotocol.pl";
use MIME::Words ();

sub process {
    my ($entity, $to) = @_;
    my $head = $entity->head;
    $head->unfold;

    my $err = sub {
        # FIXME: email error message and subject/body back
        # to $u->{email} with rate limiting.
        my $msg = shift;
        return 0;
    };

    # Get various email parts.
    my @froms = Mail::Address->parse($head->get('From:'));
    my $from = $froms[0]->address;
    my $subject = $head->get('Subject:');
    my $content_type = $head->get('Content-type:');
    my $tent = get_text_entity($entity);
    return $err->("Unable to find any text in your email.") unless $tent;
    my $body = $tent->bodyhandle->as_string;
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;

    # Snag charset and do utf-8 conversion
    my ($charset, $format);
    $charset = $1 if $content_type =~ /\bcharset=['"]?(\S+?)['"]?[\s\;]/i;
    $format = $1 if $content_type =~ /\bformat=['"]?(\S+?)['"]?[\s\;]/i;
    if (defined($charset) && $charset !~ /^UTF-?8$/i) { # no charset? assume us-ascii
        return $err->("Unknown encoding type.")
            unless Unicode::MapUTF8::utf8_supported_charset($charset);
        $body = Unicode::MapUTF8::to_utf8({-string=>$body, -charset=>$charset});
        # check subject for rfc-1521 junk 
        if ($subject =~ /^=\?/) {
            my @subj_data;
            @subj_data = MIME::Words::decode_mimewords($subject);
            if (scalar(@subj_data)) {
                $subject = Unicode::MapUTF8::to_utf8({-string=>$subj_data[0][0], -charset=>$subj_data[0][1]});
            }
        }
    }
   
    # Parse email for lj specific info                                                                                
    my ($user, $journal, $pin);                                                                                    
    ($user, $pin) = split(/\+/, $to);                                                                              
    ($user, $journal) = split(/\./, $user) if $user =~ /\./;                                                       
    my $u = LJ::load_user($user);
    return 0 unless $u;
    LJ::load_user_props($u, qw(emailpost_pin emailpost_allowfrom));

    # Strip (and maybe use) pin data from viewable areas
    if ($subject =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }
    if ($body =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }
    return $err->("No PIN specified.") unless $pin;

    # Validity checks
    my @address = split(/\s*,\s*/, $u->{emailpost_allowfrom});
    return $err->("No allowed senders have been saved for your account.")
        unless scalar(@address) > 0;
    my $ok = 0;
    foreach (@address) {
        $ok = 1 if lc eq lc($from);
    }
    return $err->("Unauthorized sender address: $from") unless $ok;
    return $err->("Invalid PIN.") unless lc($pin) eq lc($u->{emailpost_pin});
    return $err->("Email gateway access denied for your account type.")
        unless LJ::get_cap($u, "emailpost");

    $body =~ s/^[\-_]{2,}\s*\r?\n.*//ms; # trim sigs
    $body =~ s/ \n/ /g if $format eq lc('flowed'); # respect flowed text
    
    my $req = {
        'usejournal' => $journal,
        'ver' => 1,
        'username' => $user,
        'event' => $body,
        'subject' => $subject,
        'props' => {},
        'tz'    => 'guess',
    };

    my $post_error;
    my $res = LJ::Protocol::do_request("postevent", $req, \$post_error, { noauth=>1 });
    return $err->(LJ::Protocol::error_message($post_error)) if $post_error;

    return 1; 
}

# Yoinked from mailgate.  
# Probably need to make this a lib somewhere.
sub get_text_entity
{
    my $entity = shift;

    my $head = $entity->head;
    my $mime_type =  $head->mime_type;
    if ($mime_type eq "text/plain") {
        return $entity;
    }

    if ($mime_type eq "multipart/alternative" ||
        $mime_type eq "multipart/mixed") {
        my $partcount = $entity->parts;
        for (my $i=0; $i<$partcount; $i++) {
            my $alte = $entity->parts($i);
            return $alte if ($alte->mime_type eq "text/plain");
        }
        return undef;
    }

    if ($mime_type eq "multipart/related") {
        my $partcount = $entity->parts;
        if ($partcount) {
            return get_text_entity($entity->parts(0));
        }
        return undef;
    }

    $entity->dump_skeleton(\*STDERR);
    
    return undef;
}

1;
