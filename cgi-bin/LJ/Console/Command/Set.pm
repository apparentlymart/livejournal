package LJ::Console::Command::Set;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set" }

sub desc { "Set the value of a userprop." }

sub args_desc { [
                 'community' => "Optional; community to set property for, if you're a maintainer.",
                 'propname' => "Property name to set.",
                 'value' => "Value to set property to.",
                 ] }

sub usage { '[ "for" <community> ] <propname> <value>' }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("This command takes either two or four arguments. Consult the reference.")
        unless scalar(@args) == 2 || scalar(@args) == 4;

    my $remote = LJ::get_remote();
    my $journal = $remote;   # may be overridden later
    my $errmsg;
    my $rv;

    if (scalar(@args) == 4) {
        # sanity check
        my $for = shift @args;
        return $self->error("First argument must be 'for'")
            unless $for eq "for";

        my $name = shift @args;
        $journal = LJ::load_user($name);

        return $self->error("Invalid account: $name")
            unless $journal;

        my $prop = $args[0];

        if ( $prop eq 's2privs' ) {
            return $self->error("You are not permitted to change this journal's settings.")
                unless (LJ::check_priv($remote, 'siteadmin', 's2privs') && LJ::check_priv($remote, 'siteadmin', 'users')) || $LJ::IS_DEV_SERVER;

            return $self->error("No setter for property '$prop'")
                unless ref $LJ::SETTER{$prop} eq 'CODE';

            my $arg = $args[1];
            $arg =~ s/\s//g;

            if( $arg eq 'none' or $arg eq "''" or $arg eq '""' ) {
                return $self->set_privs( $journal, $remote, 's2privs', 'none', \$errmsg );
            }

            return $self->set_privs( $journal, $remote, 's2privs', $arg, \$errmsg );
        }

        return $self->error("You are not permitted to change this journal's settings.")
            unless ($remote && $remote->can_manage($journal)) || LJ::check_priv($remote, "siteadmin", "propedit");
    }

    my ($key, $value) = @args;
    return $self->error("Unknown property '$key'")
        unless ref $LJ::SETTER{$key} eq "CODE";

    $rv = $LJ::SETTER{$key}->($journal, $key, $value, \$errmsg);
    return $self->error("Error setting property: $errmsg")
        unless $rv;

    return $self->print("User property '$key' set to '$value' for " . $journal->user);
}

sub set_privs {
    my ( $self, $journal, $remote, $prop, $value, $errmsg ) = @_;
    my $rv = $LJ::SETTER{$prop}->($journal, $prop, 'none', $errmsg);

    return $self->error("Error setting property: $$errmsg")
        unless $rv;

    LJ::statushistory_add($journal, $remote, 's2privs', "s2privs set to 'none'");

    return $self->print("s2privs for " . $journal->{user} . " set to 'none'");
}

1;
