package LJ::Console::Command::ChangeCommunityAdmin;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_community_admin" }

sub desc { "Transfer maintainership of a community to another user." }

sub args_desc { [
                 'community' => "The username of the community.",
                 'new_owner' => "The username of the new owner of the community.",
                 ] }

sub usage { '<community> <new_owner>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
