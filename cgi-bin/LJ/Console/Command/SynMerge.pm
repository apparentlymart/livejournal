package LJ::Console::Command::SynMerge;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_merge" }

sub desc { "Merge two syndicated accounts into one, setting up a redirect and using one account's URL." }

sub args_desc { [
                 'from_user' => "Syndicated account to merge into another.",
                 'to_user'   => "Syndicated account to merge 'from_user' into.",
                 'url'       => "Source feed URL to use for 'to_user'. Specify the direct URL to the feed.",
                 ] }

sub usage { '<from_user> "to" <to_user> "using" <url>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "syn_edit");
}

sub execute {
    my ($self, @args) = @_;

    return 1;
}

1;
