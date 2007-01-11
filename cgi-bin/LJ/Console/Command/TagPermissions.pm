package LJ::Console::Command::TagPermissions;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "tag_permissions" }

sub desc { "Set tagging permission levels for an account." }

sub args_desc { [
                 'community' => "Optional; community to change permission levels for.",
                 'add level' => "Accounts at this level can add existing tags to entries. One of 'public', 'friends', 'private', or a custom friend group name."
                 'control level' => "Accounts at this level can do everything: add, remove, and create new ones. Value is one of 'public', 'friends', 'private', or a custom friend group name."
                 ] }

sub usage { '[ "for" <community> ] <add level> <control level>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
