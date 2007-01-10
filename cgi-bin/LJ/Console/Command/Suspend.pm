package LJ::Console::Command::Suspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "suspend" }

sub desc { "Suspend an account." }

sub args_desc { [
                 'username or email address' => "The username of the account to suspend, or an email address to suspend all accounts at that address.",
                 'reason' => "Why you're suspending the account.",
                 ] }

sub usage { '<username or email address> <reason>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
