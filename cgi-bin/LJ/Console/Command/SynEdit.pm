package LJ::Console::Command::SynEdit;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_edit" }

sub desc { "Changes the source feed URL for a syndicated account." }

sub args_desc { [
                 'user' => "The username of the syndicated account.",
                 'newurl' => "The new source feed URL.",
                 ] }

sub usage { '<user> <newurl>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "syn_edit");
}

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
