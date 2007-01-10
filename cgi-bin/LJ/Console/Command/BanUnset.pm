package LJ::Console::Command::BanUnset;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_unset" }

sub desc { "Remove a ban on a user." }

sub args_desc { [
                 'user' => "The user you want to unban.",
                 'community' => "Optional; to unban a user from a community you maintain.",
               ] }

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
