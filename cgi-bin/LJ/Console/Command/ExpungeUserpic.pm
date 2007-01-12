package LJ::Console::Command::ExpungeUserpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "expunge_userpic" }

sub desc { "Expunge a userpic from the site." }

sub args_desc { [
                 'user' => 'The username of the userpic owner.',
                 'picid' => 'The id of the userpic to expunge.',
                 ] }

sub usage { '<user> <picid>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "userpics");
}

sub execute {
    my ($self, $user, $picid, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $user && $picid && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid username $user")
        unless $u;

    # the actual expunging happens in ljlib
    my ($rval, $hookval) = LJ::expunge_userpic($u, $picid);

    if (@{$hookval || []}) {
        my ($type, $msg) = @{$hookval || []};
        $self->$type($msg);
    }

    return $self->error("Error expunging userpic.")
        unless $rval;

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, 'expunge_userpic', "expunged userpic; id=$picid");

    return $self->print("Userpic '$picid' for '$user' expunged from $LJ::SITENAMESHORT.");
}

1;
