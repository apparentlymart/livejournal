package LJ::Console::Command::ChangeCommunityAdmin;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_community_admin" }

sub desc { "Transfer maintainership of a community to another user." }

sub args_desc { [
                 'community' => "The username of the community.",
                 'new_owner' => "The username of the new owner of the community.",
                 'reason'    => "Why you are changing community admin (optional)."
                 ] }

sub usage { '<community> <new_owner> [ <reason> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "communityxfer");
}

sub execute {
    my ($self, $comm, $maint, @args) = @_;

    return $self->error("This command takes two mandatory arguments. Consult the reference")
        unless $comm && $maint;

    my $ucomm = LJ::load_user($comm);
    my $unew  = LJ::load_user($maint);

    return $self->error("Given community doesn't exist or isn't a community.")
        unless $ucomm && $ucomm->is_community;

    return $self->error("New owner doesn't exist or isn't a person account.")
        unless $unew && $unew->is_person;

    return $self->error("New owner's email address isn't validated.")
        unless $unew->{'status'} eq "A";

    # remove old maintainers' power over it
    LJ::clear_rel($ucomm, '*', 'A');

    # add a new sole maintainer
    LJ::set_rel($ucomm, $unew, 'A');

    # so old maintainers can't regain access
    LJ::User::InfoHistory->clear($ucomm);

    # change password to blank and set email of community to new maintainer's email
    LJ::update_user($ucomm, { password => '', email => $unew->email_raw });
    $ucomm->update_email_alias;

    # log to statushistory
    my $remote = LJ::get_remote();
    my $reason = '';
    $reason = join ' ', ' Reason:', @args if @args;
    LJ::statushistory_add($ucomm, $remote, "communityxfer", "Changed maintainer to ". $unew->user ." (". $unew->id .")." . $reason);
    LJ::statushistory_add($unew, $remote, "communityxfer", "Control of '". $ucomm->user ."' (". $ucomm->id .") given." . $reason);

    return $self->print("Transferred maintainership of '" . $ucomm->user . "' to '" . $unew->user . "'". $reason);
}

1;
