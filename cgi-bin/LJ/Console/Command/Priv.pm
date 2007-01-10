package LJ::Console::Command::Priv;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "priv" }

sub desc { "Grant or revoke user privileges." }

sub args_desc { [
                 'action'    => "'grant', 'revoke', or 'revoke_all' to revoke all args for a given priv",
                 'privs'     => "Comma-delimited list of priv names, priv:arg pairs, or package names (prefixed with #)",
                 'usernames' => "Comma-delimited list of usernames",
                 ] }

sub usage { '<action> <privs> <usernames>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
