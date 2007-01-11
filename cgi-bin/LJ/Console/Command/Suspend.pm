package LJ::Console::Command::Suspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "suspend" }

sub desc { "Suspend an account." }

sub args_desc { [
                 'username or email address' => "The username of the account to suspend, or an email address to suspend all accounts at that address.",
                 'reason' => "Why you're suspending the account.",
                 ] }

sub usage { '<username or email address> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "suspend");
}

sub execute {
    my ($self, @args) = @_;

    my $confirmed = 0;
    if (scalar(@args) == 3 && $args[2] eq 'confirm') {
        pop @args;
        $confirmed = 1;
    }

    return $self->error("This command takes two arguments. Consult the reference.")
        unless scalar(@args) == 2;

    my ($user, $reason) = ($args[0], $args[1]);

    my @users;
    if ($user !~ /@/) {
        push @users, $user;

    } else {
        $self->info("Acting on users matching email $user");

        my $dbr = LJ::get_db_reader();
        my $userids = $dbr->selectcol_arrayref('SELECT userid FROM email WHERE email = ?', undef, $user);
        return $self->error("Database error: " . $dbr->errstr)
            if $dbr->err;

        return $self->error("No users found matching the email address $user.")
            unless $userids && @$userids;

        my $us = LJ::load_userids(@$userids);

        foreach my $u (values %$us) {
            push @users, $u->user;
        }

        unless ($confirmed) {
            $self->info("   $_") foreach @users;
            $self->info("To actually confirm this action, please do this again:");
            $self->info("   suspend $user \"$reason\" confirm");
            return 1;
        }
    }

    foreach my $username (@users) {
        my $u = LJ::load_user($username);

        unless ($u) {
            $self->error("Unable to load '$username'");
            next;
        }

        if ($u->statusvis eq 'X') {
            $self->error("$username is purged; skipping.");
            next;
        }

        LJ::update_user($u->{'userid'}, { statusvis => 'S', raw => 'statusvisdate=NOW()' });
        $u->{statusvis} = 'S';

        my $remote = LJ::get_remote();
        LJ::statushistory_add($u, $remote, "suspend", $reason);

        $u->fb_push;
        LJ::run_hooks("account_cancel", $u);

        $self->info("User '$username' suspended.");
    }

    return 1;
}

1;
