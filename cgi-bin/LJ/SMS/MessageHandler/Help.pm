package LJ::SMS::MessageHandler::Help;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $resp = $msg->respond("this is a help message");
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*help/i ? 1 : 0;
}

1;
