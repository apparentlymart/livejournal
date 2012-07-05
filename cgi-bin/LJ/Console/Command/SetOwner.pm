package LJ::Console::Command::SetOwner;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_owner" }

sub desc { "Set user as supermaintainer for community." }

sub args_desc { [
                 'community' => "The community for which to set supermaintainer",
                 'username'  => "The username of the account to set as supermaintainer",
                 'reason'    => "Why you're setting the account as supermaintainer (optional).",
                 ] }

sub usage { '<community> <username> [ <reason> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "elections");
}

sub execute {
    my ($self, $comm, $user, @args) = @_;

    return $self->error("This command takes two mandatory arguments. Consult the reference.")
        unless $comm && $user;

    my $remote = LJ::get_remote();
    my $c = LJ::load_user($comm);
    my $u = LJ::load_user($user);

    unless ($u) {
        $self->error("Unable to load '$user'");
        next;
    }

    unless ($c) {
        $self->error("Unable to load '$comm'");
        next;
    }

    my $s_maints = LJ::load_rel_user($c->{userid}, 'S');
    my $s_maint_us = @$s_maints ? LJ::load_userids(@$s_maints) || {} : {};
    if (%$s_maint_us) {
        foreach my $u (values %$s_maint_us) {
            LJ::clear_rel($c->{userid}, $u->{userid}, 'S');
        }
    }

    $c->log_event('set_owner', { actiontarget => $u->{userid}, remote => $remote });

    ## Close election poll if exist and open
    my $poll_id = $c->prop("election_poll_id");
    if ($poll_id) {
        my $poll = LJ::Poll->new ($poll_id);
        if ($poll && !$poll->is_closed) {
            $self->print("Election poll with ID: $poll_id closed.");
            $poll->close_poll;
        }
    }

    my $reason = '';
    $reason = join ' ', '. Reason: ', @args if @args;
    LJ::statushistory_add($c, $remote, 'set_owner', "Console set owner and new maintainer as " . $u->{'user'}. $reason);
    LJ::set_rel($c->{userid}, $u->{userid}, 'S');
    ## Set a new supermaintainer as maintainer too.
    LJ::set_rel($c->{userid}, $u->{userid}, 'A');
    $c->log_event('maintainer_add', { actiontarget => $u->{userid}, remote => $remote });

    $self->print("User '$user' setted as supermaintainer for '$comm'". $reason);

    return 1;
}

1;
