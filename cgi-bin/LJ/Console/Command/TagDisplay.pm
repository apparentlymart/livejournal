package LJ::Console::Command::TagDisplay;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_display" }

sub desc { "Set tag visibility to S2." }

sub args_desc { [
                 'community' => "Community that this tag is in, if applicable.",
                 'tag' => "The tag to change the display value of.  This must be quoted if it contains any spaces.",
                 'value' => "Either 'on' to display tag, or 'off' to hide it.",
                 ] }

sub usage { '[ "for" <community> ] <tag> <value>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
