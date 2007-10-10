package LJ::Console::Command::SetAdult;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_adult" }

sub desc { "Set the adult content flag for an account or an entry." }

sub args_desc { [
                 'content' => "The username of the account or the URL of the entry",
                 'state' => "Either 'none' (no adult content), 'concepts' (adult concepts), 'explicit' (explicit adult content), or 'default' (journal default; for entries only)",
                 'reason' => "Reason why the action is being done",
                 ] }

sub usage { '<content> <state> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::is_enabled("content_flag") && $remote && $remote->can_admin_content_flagging ? 1 : 0;
}

sub execute {
    my ($self, $content, $state, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $content && $state && $reason && scalar(@args) == 0;

    # check to see if it's a user or an entry
    my $u = LJ::load_user($content);
    my $entry = LJ::Entry->new_from_url($content);
    my ($type, $content_obj, $for_u);
    if ($u && !$entry) {
        $type = "Journal";
        $content_obj = $u;
        $for_u = $u;
    } elsif (!$u && $entry) {
        $type = "Entry";
        $content_obj = $entry;
        $for_u = $entry->journal;
    } else {
        return $self->error("First argument must be either a username or the URL to an entry.");
    }

    if ($type eq "Journal") {
        return $self->error("Second argument must be either 'none', 'concepts', or 'explicit'.")
            unless $state =~ /^(?:none|concepts|explicit)$/;
    } else { # entry
        return $self->error("Second argument must be either 'none', 'concepts', 'explicit', or 'default'.")
            unless $state =~ /^(?:none|concepts|explicit|default)$/;
    }

    my $msg_for_state;
    if ($state eq "none") {
        $msg_for_state = "no adult content";
    } elsif ($state eq "concepts") {
        $msg_for_state = "adult concepts";
    } elsif ($state eq "explicit") {
        $msg_for_state = "explicit adult content";
    } elsif ($state eq "default") {
        $msg_for_state = "the journal's adult content level";
    }

    return $self->error("$type is already flagged as containing $msg_for_state.")
        if $content_obj->adult_content eq $state;

    if ($state eq "default") {
        $content_obj->set_prop("adult_content", "");
    } else {
        $content_obj->set_prop("adult_content", $state);
    }
    $self->print("$type has been flagged as containing $msg_for_state.");

    my $remote = LJ::get_remote();
    if ($type eq "Journal") {
        LJ::statushistory_add($for_u, $remote, "set_adult", "journal flagged as $state: " . $reason);
    } else { # entry
        LJ::statushistory_add($for_u, $remote, "set_adult", "$content flagged as $state: " . $reason);
    }

    return 1;
}

1;
