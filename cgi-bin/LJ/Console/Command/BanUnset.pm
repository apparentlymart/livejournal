package LJ::Console::Command::BanUnset;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_unset" }

sub desc { "Remove a ban on a user." }

sub args_desc { [
                 'user' => "The user you want to unban.",
                 'community' => "Optional; to unban a user from a community you maintain.",
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
    return $self->error("Unknown account: $args[0]")
        unless $banuser;

    LJ::clear_rel($journal, $banuser, 'B');
    $journal->log_event('ban_unset', { actiontarget => $banuser, remote => $remote });

    return $self->print("User " . $banuser->user . " unbanned from " . $journal->user);
}

1;
