package LJ::Console::Command::MoodthemePublic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_public" }

sub desc { "Mark a mood theme as public or not." }

sub args_desc { [
                 'themeid' => "Mood theme ID number.",
                 'setting' => "Either 'Y' or 'N' to make it public or not public, respectively.",
                 ] }

sub usage { '<themeid> <setting>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
