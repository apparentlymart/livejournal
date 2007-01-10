package LJ::Console::Command::GetModerator;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_moderator" }

sub desc { "Given a community username, lists all moderators. Given a user account, lists all communities that the user moderates." }

sub args_desc { [
                 'user' => "The username of the account you want to look up.",
                 ] }

sub usage { '<user>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
