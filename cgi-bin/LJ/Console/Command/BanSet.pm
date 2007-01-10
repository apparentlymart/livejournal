package LJ::Console::Command::BanSet;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_set" }

sub desc { "Ban another user from posting in your journal or community." }

sub args_desc { [
                 'user' => "The user you want to ban.",
                 'community' => "Optional; to ban a user from a community you maintain.",
               ] }

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
