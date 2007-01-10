package LJ::Console::Command::SetUnderage;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_underage" }

sub desc { "Change an account's underage status." }

sub args_desc { [
                 'user' => "The username of the journal to mark/unmark",
                 'state' => "Either 'on' (to mark as being underage) or 'off' (to unmark)",
                 'note' => "Required information about why you are setting this status.",
                 ] }

sub usage { '<user> <state> <note>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
