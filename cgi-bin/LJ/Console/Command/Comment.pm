package LJ::Console::Command::Comment;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "comment" }

sub desc { "Manage comments in an account." }

sub args_desc { [
                 'action' => 'One of: screen, unscreen, freeze, unfreeze, delete, delete_thread.',
                 'url' => 'The URL to the comment. (Use the permanent link that shows this comment topmost.)',
                 'reason' => 'Reason this action is being taken.',
                 ] }

sub usage { '<action> <url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "suspend");
 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless scalar(@args) == 3;

    my ($action, $uri, $reason) = @args;

    return $self->error("Action must be one of: screen, unscreen, freeze, unfreeze, delete, delete_thread.")
        unless $action =~ /^(?:screen|unscreen|freeze|unfreeze|delete|delete_thread)$/;

    return $self->error("URL must be a valid URI in format: $LJ::SITEROOT/users/username/1234.html?thread=1234.")
        unless $uri =~ m!^$LJ::SITEROOT/(?:users|community)/(.+?)/(\d+)\.html\?thread=(\d+)!;

    my ($user, $ditemid, $dtalkid) = ($1, $2, $3);
    my $u = LJ::load_user($user);
    my $jitemid = $ditemid >> 8;
    my $jtalkid = $dtalkid >> 8;
    return $self->error("URL provided does not appear to be valid?")
        unless $u && $jitemid && $jtalkid;
    return $self->error("You must provide a reason to action a comment.")
        unless $reason;

    # now load up the comment and see if action needs taking
    my $td = LJ::Talk::get_talk_data($u, 'L', $jitemid);
    return $self->error("Unable to fetch talk data for entry.")
        unless $td;

    my $cmt = $td->{$jtalkid};
    return $self->error("Unable to locate comment in talk data from entry.")
        unless $cmt;
    return $self->error("The comment is already deleted, so no further action is possible.")
        if $cmt->{state} eq 'D';

    if ($action eq 'freeze') {
        return $self->error("Comment is already frozen.")
            if $cmt->{state} eq 'F';
        LJ::Talk::freeze_thread($u, $jitemid, $jtalkid);

    } elsif ($action eq 'unfreeze') {
        return $self->error("Comment is not frozen.")
            unless $cmt->{state} eq 'F';
        LJ::Talk::unfreeze_thread($u, $jitemid, $jtalkid);

    } elsif ($action eq 'screen') {
        return $self->error("Comment is already screened.")
            if $cmt->{state} eq 'S';
        LJ::Talk::screen_comment($u, $jitemid, $jtalkid);

    } elsif ($action eq 'unscreen') {
        return $self->error("Comment is not screened.")
            unless $cmt->{state} eq 'S';
        LJ::Talk::unscreen_comment($u, $jitemid, $jtalkid);

    } elsif ($action eq 'delete') {
        LJ::Talk::delete_comment($u, $jitemid, $jtalkid, $cmt->{state});

    } elsif ($action eq 'delete_thread') {
        LJ::Talk::delete_thread($u, $jitemid, $jtalkid);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, 'comment_action', "$action (entry $ditemid comment $dtalkid): $reason");

    return $self->print("Comment action taken.");
}

1;
