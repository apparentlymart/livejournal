package LJ::Console::Command::SetBadpassword;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_badpassword" }

sub desc { "Mark or unmark an account as having a bad password." }

sub args_desc { [
                 'user' => "The username of the journal to mark/unmark",
                 'state' => "Either 'on' (to mark as having a bad password) or 'off' (to unmark)",
                 'note' => "Required information about why you are setting this status.",
                 ] }

sub usage { '<user> <state> <note>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
