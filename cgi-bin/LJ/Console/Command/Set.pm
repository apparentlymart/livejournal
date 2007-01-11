package LJ::Console::Command::Set;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set" }

sub desc { "Set the value of a userprop." }

sub args_desc { [
                 'community' => "Optional; community to set property for, if you're a maintainer.",
                 'propname' => "Property name to set.",
                 'value' => "Value to set property to.",
                 ] }

sub usage { '[ "for" <community> ] <propname> <value>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
