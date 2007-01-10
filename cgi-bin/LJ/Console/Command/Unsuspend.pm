package LJ::Console::Command::Unsuspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "unsuspend" }

sub desc { "Unsuspend an account." }

sub args_desc { [
                 'username or email address' => "The username of the account to unsuspend, or an email address to unsuspend all accounts at that address.",
                 'reason' => "Why you're unsuspending the account.",
                 ] }

sub usage { '<username or email address> <reason>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
