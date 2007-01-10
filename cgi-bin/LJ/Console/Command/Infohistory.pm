package LJ::Console::Command::Infohistory;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "infohistory" }

sub desc { "Retrieve info history of a given account." }

sub args_desc { [
                 'user' => "The username of the account whose infohistory to retrieve.",
                 ] }

sub usage { '<user>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
