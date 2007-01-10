package LJ::Console::Command::MoodthemeList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_list" }

sub desc { "List mood themes, or data about a mood theme." }

sub args_desc { [
                 'themeid' => 'Optional; mood theme ID to view data for. If not given, lists all available mood themes.'
                 ] }

sub usage { '[ <themeid> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
