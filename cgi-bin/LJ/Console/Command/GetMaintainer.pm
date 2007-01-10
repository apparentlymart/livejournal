package LJ::Console::Command::GetMaintainer;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_maintainer" }

sub desc { "Given a community username, lists all maintainers. Given a user account, lists all communities that the user maintains." }

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
