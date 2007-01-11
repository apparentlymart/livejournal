package LJ::Console::Command::BanSet;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_set" }

sub desc { "Ban another user from posting in your journal or community." }

sub args_desc { [
                 'user' => "The user you want to ban.",
                 'community' => "Optional; to ban a user from a community you maintain.",
               ] }

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless scalar(@args) == 3 || scalar(@args) == 1;

    if (scalar(@args) == 3) {
        return $self->error("First argument must be 'from'")
            if $args[1] ne "from";

        $journal = LJ::load_user($args[2]);
        return $self->error("Unknown account: $args[2]")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless LJ::can_manage($remote, $journal);
    }

    my $banuser = LJ::load_user($args[0]);

    my $banlist = LJ::load_rel_user($journal, 'B') || [];
    return $self->error("You have reached the maximum number of bans.  Unban someone and try again.")
        if scalar(@$banlist) >= ($LJ::MAX_BANS || 5000);

    LJ::set_rel($journal, $banuser, 'B');
    $journal->log_event('ban_set', { actiontarget => $banuser, remote => $remote });

    return $self->print("User " . $banuser->user . " banned from " . $journal->user);
}

1;
