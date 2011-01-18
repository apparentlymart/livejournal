package LJ::Console::Command::SetOwner;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_owner" }

sub desc { "Set user as supermaintainer for community." }

sub args_desc { [
                 'community' => "The community for which to set supermaintainer",
                 'username'  => "The username of the account to set as supermaintainer",
                 'reason'    => "Why you're setting the account as supermaintainer.",
                 ] }

sub usage { '<community> <username> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "elections");
}

sub execute {
    my ($self, $comm, $user, $reason, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $comm && $user && scalar(@args) == 0;

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

    #LJ::statushistory_add($u, $remote, "suspend", $reason);
    my $s_maints = LJ::load_rel_user($c->{userid}, 'S');
    my $s_maint_u = @$s_maints ? LJ::load_userid($s_maints->[0]) : undef;
    if ($s_maint_u) {
        LJ::clear_rel($c->{userid}, $s_maint_u->{userid}, 'S');
    }

    LJ::set_rel($c->{userid}, $u->{userid}, 'S');

    $self->print("User '$user' setted as supermaintainer for '$comm'.");

    return 1;
}

1;
