package LJ::Console::Command::GetRelation;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_relation" }

sub desc { "Given a username and an edge, looks up all relations." }

sub args_desc { [
                 'user' => "The username of the account you want to look up.",
                 'edge' => "The reluser edge to look up.",
                 ] }

sub usage { '<user> <edge>' }

sub can_execute { 0 }  # can't be called directly

sub execute {
    my ($self, @args) = @_;

    return $self->error("This command takes exactly two arguments. Consult the reference.")
        unless scalar(@args) == 2;

    my ($user, $edge) = @args;
    my $u = LJ::load_user($user);
    return $self->error("Invalid user $user")
        unless $u;

    my @ids = $u->is_person ? LJ::load_rel_target($u, $edge) : LJ::load_rel_user($u, $edge);

    foreach my $id (@ids) {
        my $finduser = LJ::Console::Command::Finduser->new( command => 'finduser', args => [ 'userid', $id ] );
        $finduser->execute;
        $self->add_responses($finduser->responses);
    }

    return 1;
}

1;
