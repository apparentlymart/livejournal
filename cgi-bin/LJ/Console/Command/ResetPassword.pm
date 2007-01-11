package LJ::Console::Command::ResetPassword;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "reset_password" }

sub desc { "Resets the password for a given account" }

sub args_desc { [
                 'user' => "The account to reset the email address for.",
                 'reason' => "Reason for the password reset.",
                 ] }

sub usage { '<user> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "reset_email");
}

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
