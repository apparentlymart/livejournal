# LJ::Console family of libraries
#
# Initial structure:
#
# LJ::Console.pm                 # wrangles commands, parses input, etc
# LJ::Console::Command.pm        # command base class
# LJ::Console::Command::Foo.pm   # individual command implementation
# LJ::Console::Response.pm       # success/failure, very simple
#
# Usage:
#
# my $out_html = LJ::Console->run_commands_html($user_input);
# my $out_text = LJ::Console->run_commands_text($user_text);
#

package LJ::Console;

use strict;
use Carp qw(croak);

# Fill with class methods (mostly from console.pl)

sub run_commands {
    my $class = shift;
    my $text  = shift;
    
    # which command objects are represented in this
    # text input from the user?
    my $out = "";
    my @commands = LJ::Console->parse_text($text);

    foreach my $cmd (@commands) {
        $out .= $cmd->execute;
    }

    return $out;
}

1;
