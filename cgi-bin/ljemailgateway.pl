#!/usr/bin/perl

package LJ::Emailpost;
use strict;
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljprotocol.pl";

sub process {
    my ($to, $subject, $body, $from) = @_;
    my ($user, $journal, $pin);

    ($user, $pin) = split(/\+/, $to);
    ($user, $journal) = split(/\./, $user) if $user =~ /\./;
    return 0 unless $user;

    my $u = LJ::load_user($user);
    return 0 unless $u;
    LJ::load_user_props($u, qw(emailpost_pin emailpost_allowfrom));

    my $err = sub {
        # FIXME: email error message and subject/body back
        # to $u->{email} with rate limiting.
        my $msg = shift;
        return 0;
    };

    if ($subject =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }
    if ($body =~ s/^\s*\+([a-z0-9]+)\s+//i) {
        $pin = $1 unless defined $pin;
    }
    return $err->("No PIN specified.") unless $pin;

    my @address = split(/\s*,\s*/, $u->{emailpost_allowfrom});
    my $ok = 0;
    foreach (@address) {
        $ok = 1 if lc eq lc($from);
    }
    return $err->("Unauthorized sender address: $from") unless $ok;
    return $err->("Invalid PIN.") unless lc($pin) eq lc($u->{emailpost_pin});

    return $err->("Email gateway access denied for your account type.")
        unless LJ::get_cap($u, "emailpost");

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

1;
