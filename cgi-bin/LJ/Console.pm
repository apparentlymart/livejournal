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

# takes a set of console commands, returns command objects
sub parse_text {
    my $class = shift;
    my $text = shift;

    my @commands;

    foreach my $line (split(/\n/, $text)) {
        @args = LJ::Console->parse_line($line);
        # first arg is the command, anything after is the args
        # find the handler and create a new command object,
        # then push onto @commands
    }

}

# parses each console command, parses out the arguments
sub parse_line {
    my $class = shift;
    my $cmd = shift;

    return () unless $cmd =~ /\S/;

    $cmd =~ s/^\s+//;
    $cmd =~ s/\s+$//;
    $cmd =~ s/\t/ /g;

    my $state = 'a';  # w=whitespace, a=arg, q=quote, e=escape (next quote isn't closing)

    my @args;
    my $argc = 0;
    my $len = length($cmd);
    my ($lastchar, $char);

    for (my $i=0; $i < $len; $i++) {
        $lastchar = $char;
        $char = substr($cmd, $i, 1);

        ### jump out of quots
        if ($state eq "q" && $char eq '"') {
            $state = "w";
            next;
        }

        ### keep ignoring whitespace
        if ($state eq "w" && $char eq " ") {
            next;
        }

        ### finish arg if space found
        if ($state eq "a" && $char eq " ") {
            $state = "w";
            next;
        }

        ### if non-whitespace encountered, move to next arg
        if ($state eq "w") {
            $argc++;
            if ($char eq '"') {
                $state = "q";
                next;
            } else {
                $state = "a";
            }
        }

        ### don't count this character if it's a quote
        if ($state eq "q" && $char eq '"') {
            $state = "w";
            next;
        }

        ### respect backslashing quotes inside quotes
        if ($state eq "q" && $char eq "\\") {
            $state = "e";
            next;
        }

        ### after an escape, next character is literal
        if ($state eq "e") {
            $state = "q";
        }

        $args[$argc] .= $char;
    }

    return @args;
}


# parses user input, returns an array of response objects
sub run_commands {
    my $class = shift;
    my $text  = shift;

    # which command objects are represented in this
    # text input from the user?
    my @responses;
    my @commands = LJ::Console->parse_text($text);

    push @responses, $_->execute foreach @commands;

    return @responses;
}

# takes a set of response objects and returns string implementation
sub run_commands_text {
    my $class = shift;
    my $text = shift;

    my @responses = LJ::Console->run_commands($text);
    my $out = join("\n", map { $_->as_string } @responses);

    return $out;
}

sub run_commands_html {
    my $class = shift;
    my $text = shift;

    my @responses = LJ::Console->run_commands($text);
    my $out = join("<br />", map { $_->as_string } @responses);

    return $out;
}

sub success_response {
    my $class = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'success', text => $text );
}

sub error_response {
    my $class = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'error', text => $text );
}

sub info_response {
    my $class = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'info', text => $text );
}

1;
