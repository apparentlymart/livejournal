package LJ::Console::Command::ResetEmail;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "reset_email" }

sub desc { "Resets the email address of a given account." }

sub args_desc { [
                 'user' => "The account to reset the email address for.",
                 'value' => "Email address to set the account to.",
                 'reason' => "Reason for the reset",
                 ] }

sub usage { '<user> <value> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "reset_email");
}

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
