package LJ::SMS::MessageHandler;

# LJ::SMS::MessageHandler object
#  - Base class for all LJ::SMS Message Handlers
#

use strict;
use Carp qw(croak);

my @HANDLERS = ();

BEGIN {
    #@LJ::SMS::MessageHandler::HANDLERS = qw();
    @HANDLERS = qw();

    foreach my $handler (@HANDLERS) {
        eval "use LJ::SMS::MessageHandler::$handler";
        die "Error loading MessageHandler '$handler': $@" if $@;
    }
}

sub handle_msg {
    my ($class, $msg) = @_;
    croak "msg argument must be a valid LJ::SMS::Message object"
        unless $msg && $msg->isa("LJ::SMS::Message");

    foreach my $handler (@HANDLERS) {
        $handler->handle_msg($msg) if $handler->owns_msg($msg);
    }
}

sub owns_msg {
    my ($class, $msg) = @_;

    warn "STUB: LJ::SMS::MessageHandler->owns_msg";
    return 0;
}

1;
