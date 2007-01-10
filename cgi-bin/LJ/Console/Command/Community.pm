package LJ::Console::Command::Community;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "community" }

sub desc { "Add or remove a user from a community." }

sub args_desc { [
                 'community' => "The username of the community.",
                 'action' => "Only 'remove' is supported right now.",
                 'user' => "The user you want to remove from the community.",
                 ] }

sub usage { '<community> <action> <user>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
