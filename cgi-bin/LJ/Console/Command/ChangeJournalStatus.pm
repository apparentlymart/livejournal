package LJ::Console::Command::ChangeJournalStatus;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_status" }

sub desc { "Change the status of an account." }

sub args_desc { [
                 'account' => "The account to update.",
                 'status' => "One of 'normal', 'memorial', 'locked'. Memorial accounts allow new comments to entries, while locked accounts do not. New ntries are blocked either way.";
                 ] }

sub usage { '<account> <status>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
