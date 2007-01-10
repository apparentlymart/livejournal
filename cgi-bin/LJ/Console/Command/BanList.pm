package LJ::Console::Command::BanList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_list" }

sub desc { "Lists users who are banned from an account." }

sub args_desc { [
                 'user' => "Optional; lists bans in a community you maintain, or any user if you have the 'finduser' priv."
                 ] }

sub usage { '[ "from" <user> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    if (scalar(@args) == 2) {
        return $self->error("First argument must be 'from'")
            if @args[0] ne "from";

        $journal = LJ::load_user(@args[1]);
        return $self->error("Unknown account: @args[1]")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless LJ::can_manage($remote, $journal) || LJ::check_priv($remote, "finduser");
    }

    my $banids = LJ::load_rel_user($journal, 'B') || [];
    my $us = LJ::load_userids(@$banids);
    my @userlist = map { $us->{$_}{user} } keys %$us;

    return $self->info($j->user . " has not banned any other users.")
        unless @userlist;

    $self->info($_) foreach @userlist;

    return 1;
}

1;
