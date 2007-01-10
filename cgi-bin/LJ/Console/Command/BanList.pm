package LJ::Console::Command::BanList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_list" }

sub desc { "Lists users who are banned from an account." }

sub args_desc { [
                 'user' => "Optional; lists bans in a community you maintain, or any user if you have the 'finduser' priv."
                 ] }

sub usage { '[ "from" <user> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
