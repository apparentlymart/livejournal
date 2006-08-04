package LJ::SMS::MessageHandler;

# LJ::SMS::MessageHandler object
#  - Base class for all LJ::SMS Message Handlers
#

use strict;
use Carp qw(croak);

my @HANDLERS = ();

BEGIN {
    @HANDLERS = map { "LJ::SMS::MessageHandler::$_" }
                qw(Post Help Echo);

    foreach my $handler (@HANDLERS) {
        eval "use $handler";
        die "Error loading MessageHandler '$handler': $@" if $@;
    }
}

sub handle {
    my ($class, $msg) = @_;
    croak "msg argument must be a valid LJ::SMS::Message object"
        unless $msg && $msg->isa("LJ::SMS::Message");

    foreach my $handler (@HANDLERS) {
        $handler->handle($msg) if $handler->owns($msg);
    }
}

sub owns {
    my ($class, $msg) = @_;

    warn "STUB: LJ::SMS::MessageHandler->owns";
    return 0;
}

1;
