package LJ::Console::Command::Help;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "help" }

sub desc { "Get help on console commands." }

sub args_desc { [
                  'command' => "A command to get help on. If omitted, prints help for all commands.",
                  ] }

sub usage { '[ <command> ]' }

sub requires_remote { 0 }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
