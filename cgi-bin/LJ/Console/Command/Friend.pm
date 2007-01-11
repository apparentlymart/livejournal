package LJ::Console::Command::Friend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "friend" }

sub desc { "List your friends or add/remove a user from your friends list." }

sub args_desc { [
                 'command' => "Either 'list' to list friend, 'add' to add a friend, or 'remove' to remove a friend.",
                 'user' => "The username of the person to add or remove when using the add or remove command.",
                 'group' => "Optional; when using 'add', adds the user to this friend group. It must already exist.",
                 'fgcolor' => "Optional; when using 'add', specifies the foreground color. Must be of form 'fgcolor=#hex'",
                 'bgcolor' => "Optional; when using 'add', specifies the background color. Must be of form 'bgcolor=#hex'",
                 ] }

sub usage { '<command> <user> [ <group> ] [ <fgcolor> ] [ <bgcolor> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
