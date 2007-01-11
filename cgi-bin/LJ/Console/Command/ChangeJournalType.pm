package LJ::Console::Command::ChangeJournalType;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_type" }

sub desc { "Change a journal's type." }

sub args_desc { [
                 'journal' => "The username of the journal that type is changing.",
                 'type' => "Either 'person', 'shared', or 'community'.",
                 'owner' => "This is required when converting a personal journal to a community or shared journal, or the reverse. If converting to a community/shared journal, 'owner' will become the maintainer. Otherwise, the account will adopt the email address and password of the 'owner'. Only users with the 'changejournaltype' priv can specify an owner for an account.",
                 ] }

sub usage { '<journal> <type> [ <owner> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
