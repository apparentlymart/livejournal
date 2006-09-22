package LJ::SMS::MessageHandler;

# LJ::SMS::MessageHandler object
#  - Base class for all LJ::SMS Message Handlers
#

use strict;
use Carp qw(croak);

use LJ::ModuleLoader;

my @HANDLERS = module_subclasses("LJ::SMS::MessageHandler");
foreach my $handler (@HANDLERS) {
    eval "use $handler";
    die "Error loading MessageHandler '$handler': $@" if $@;
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
        $found++;

        # note the handler type for this message
        my $htype = (split('::', $handler))[-1];
        $msg->meta(handler_type => $htype);

        # also store as the message's class_type
        $msg->class_key("${htype}-Request");

        # get the user that this message is destined for
        my $u = $msg->from_u;
        unless ($u) {
            $msg->status('error' => "No destination user");
            return 1;
        }

        # don't handle the message if the user is unverified
        # UNLESS the handler accepts unverified users
        if ($u->sms_pending_number) {
            # user is awaiting verification.
            unless ($handler->unverified_user_ok($u)) {
                $msg->status('error' => "Message from unverified user");
                return 1;
            }
        }

        # handle the message
        if ($u->is_visible) {
            eval { $handler->handle($msg) };
            if ($@) {
                $msg->status('error' => $@);
                warn "Error handling message with handler $handler: $@" if $LJ::IS_DEV_SERVER;
            }
        } else {
            # suspended account
            $msg->status('error' => "Incoming SMS from inactive user");
        }

        # message handler should update the status to one
        # of 'success' or 'error' ...
        croak "after handling, msg status: " . $msg->status . ", should be set?"
            if ! $msg->status || $msg->status eq 'unknown';

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

# does this handler accept messages from unverified users?
sub unverified_user_ok {
    my ($class, $u) = @_;

    return 0;
}

1;
