package LJ::Console::Command::Shared;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "shared" }

sub desc { "Add or remove posting access in a shared journal." }

sub args_desc { [
                 'sharedjournal' => "The username of the shared journal.",
                 'action' => "Either 'add' or 'remove'.",
                 'user' => "The user you want to add or remove from posting in the shared journal.",
                 ] }

sub usage { '<sharedjournal> <action> <user>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
