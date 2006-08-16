package LJ::SMS::MessageHandler::Stop;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    $msg->reply("Are you sure you want to disable the $LJ::SITENAMEABBREV SMS program? ".
                "Send YES to confirm. Other charges may apply.", no_quota => 1);

    $msg->from_u->set_prop('sms_yes_means', 'stop');

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    my @synonyms = qw (
                       stop
                       end
                       cancel
                       unsubscribe
                       quit
                       );

    foreach my $syn (@synonyms) {
        return 1 if $msg->body_text =~ /^\s*$syn/i;
    }

    return 0;
}

1;
