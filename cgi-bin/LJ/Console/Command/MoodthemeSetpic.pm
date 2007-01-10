package LJ::Console::Command::MoodthemeSetpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_setpic" }

sub desc { "Change data for a mood theme. If picurl, width, or height is empty or zero, the data is deleted." }

sub args_desc { [
                 'themeid' => "Mood theme ID number.",
                 'moodid' => "Mood ID number.",
                 'picurl' => "URL of picture for this mood. Use /img/mood/themename/file.gif for public mood images",
                 'width' => "Width of picture",
                 'height' => "Height of picture",
                 ] }

sub usage { '<themeid> <moodid> <picurl> <width> <height>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
