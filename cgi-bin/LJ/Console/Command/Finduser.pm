package LJ::Console::Command::Finduser;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "finduser" }

sub desc { "Finds all accounts matching a certain criterion." }

sub args_desc { [
                 'criteria' => "One of: 'user', 'userid', or 'email'.",
                 'data' => "Either a username, userid, or email address.",
                 ] }

sub usage { '<criteria> <data>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
