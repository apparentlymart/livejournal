package LJ::SMS::MessageHandler;

# LJ::SMS::MessageHandler object
#  - Base class for all LJ::SMS Message Handlers
#

use strict;
use Carp qw(croak);

my @HANDLERS = ();

BEGIN {
    @HANDLERS = map { "LJ::SMS::MessageHandler::$_" }
                qw(Post PostComm Help Echo ILike Add Menu);

    foreach my $handler (@HANDLERS) {
        eval "use $handler";
        die "Error loading MessageHandler '$handler': $@" if $@;
    }
}

sub handle {
    my ($class, $msg) = @_;
    croak "msg argument must be a valid LJ::SMS::Message object"
        unless $msg && $msg->isa("LJ::SMS::Message");

    # save msg to the db
    $msg->save_to_db
        or die "unable to save message to db";

    my $found = 0;
    foreach my $handler (@HANDLERS) {
        next unless $handler->owns($msg);

        # note the handler type for this message
        my $htype = (split('::', $handler))[-1];
        $msg->meta(handler_type => $htype);

        # handle the message
        eval { $handler->handle($msg) };
        $msg->status('error' => $@) if $@;

        # message handler should update the status to one
        # of 'success' or 'error' ...
        die "after handling, msg status: " . $msg->status . ", should be set?"
            if ! $msg->status || $msg->status eq 'unknown';

        $found++;
        last;
    }

    # did any handler claim this message?
    $msg->status('error' => "Invalid command matched no handler")
        unless $found;

    return 1;
}

sub owns {
    my ($class, $msg) = @_;

    warn "STUB: LJ::SMS::MessageHandler->owns";
    return 0;
}

1;
