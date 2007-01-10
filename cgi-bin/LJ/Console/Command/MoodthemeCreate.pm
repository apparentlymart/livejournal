package LJ::Console::Command::MoodthemeCreate;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_create" }

sub desc { "Create a new moodtheme. Returns the mood theme ID that you'll need to define moods for this theme." }

sub args_desc { [
                 'name' => "Name of this theme."
                 'desc' => "A description of the theme",
                 ] }

sub usage { '<name> <desc>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
