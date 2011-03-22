package LJ::Console::Command::Unsuspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "unsuspend" }

sub desc { "Unsuspend an account or entry. Or unmark entries made by already unsuspended account." }

sub args_desc { [
                 '--unmark' => "Optional flag to not check 'suspended' status but simply put job for worker to unmark again. Not applicable to entry level.",
                 'username or email address or entry url' => "The username of the account to unsuspend, or an email address to unsuspend all accounts at that address, or an entry URL to unsuspend a single entry within an account",
                 'reason' => "Why you're unsuspending the account or entry",
                 ] }

sub usage { '[--unmark] <username or email address or entry url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return      LJ::check_priv($remote, "suspend")
            ||  LJ::check_priv($remote, "unsuspend");
}

sub execute {
    my ($self, $flag_unmark, $user, $reason, $confirmed, @args) = @_;
    if (lc($flag_unmark) ne '--unmark') {
        unshift @args, $confirmed if defined $confirmed;
        $confirmed = $reason;
        $reason = $user;
        $user = $flag_unmark;
        $flag_unmark = undef;
    }

    return $self->error("This command takes two arguments (and one optional flag). Consult the reference.")
        unless $user && $reason && scalar(@args) == 0;

    my $remote = LJ::get_remote();
    my $entry = LJ::Entry->new_from_url($user);
    if ($entry) {
        my $poster = $entry->poster;
        my $journal = $entry->journal;

        return $self->error("Invalid entry.")
            unless $entry->valid;

        return $self->error("Journal and/or poster is purged; cannot unsuspend entry.")
            if $poster->is_expunged || $journal->is_expunged;

        return $self->error("Entry is not currently suspended.")
            if $entry->is_visible;

        $entry->set_prop( statusvis => "V" );
        $entry->set_prop( unsuspend_supportid => 0 )
            if $entry->prop("unsuspend_supportid");

        $entry->mark_suspended('N'); # return in LJ::get_recent_items() call

        $reason = "entry: " . $entry->url . "; reason: $reason";
        LJ::statushistory_add($journal, $remote, "unsuspend", $reason);
        LJ::statushistory_add($poster, $remote, "unsuspend", $reason)
            unless $journal->equals($poster);

        return $self->print("Entry " . $entry->url . " unsuspended.");
    }

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

        unless ($confirmed eq "confirm") {
            $self->info("   $_") foreach @users;
            $self->info("To actually confirm this action, please do this again:");
            $self->info("   unsuspend $user \"$reason\" confirm");
            return 1;
        }
    }

    foreach my $username (@users) {
        my $u = LJ::load_user($username);

        unless ($u) {
            $self->error("Unable to load '$username'");
            next;
        }

        unless ($flag_unmark) {

            unless ($u->is_suspended) {
                $self->error("$username is not currently suspended; skipping.");
                next;
            }

            ## Restore previous statusvis of journal. It may be different
            ## from 'V', it may be read-only, or locked, or whatever.
            my @previous_status;
            if ($u->clusterid) { # purged user has no cluster, but can be suspended
                @previous_status = grep { $_ ne 'S' } $u->get_previous_statusvis;
            } else { # was purged - no data any more
                @previous_status = ('X');
            }
            my $new_status = $previous_status[0] || 'V';
            my $method = {
                V => 'set_visible',
                L => 'set_locked',
                M => 'set_memorial',
                O => 'set_readonly',
                R => 'set_renamed',
                X => 'set_expunged',
                D => 'set_deleted',
            }->{$new_status};

            unless ($method) {
                $self->error("Can't set status '$new_status'");
                next;
            }

            my $res = $u->$method;

            $u->{statusvis} = $new_status;

        }

        my $job = TheSchwartz::Job->new_from_array("LJ::Worker::MarkSuspendedEntries::unmark", { userid => $u->userid });
        my $sclient = LJ::theschwartz();
        $sclient->insert_jobs($job) if $sclient and $job and LJ::is_enabled('mark_suspended_accounts');

        unless ($flag_unmark) {
            LJ::statushistory_add($u, $remote, "unsuspend", $reason);
            eval { $u->fb_push };
            warn "Error running fb_push: $@\n" if $@ && $LJ::IS_DEV_SERVER;

            $self->print("User '$username' unsuspended.");
        } else {
            $self->print("Unmark job put for '$username' user.");
        }
    }

    return 1;
}

1;
