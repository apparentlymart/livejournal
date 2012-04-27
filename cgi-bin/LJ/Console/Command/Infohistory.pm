package LJ::Console::Command::Infohistory;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "infohistory" }

sub desc { "Retrieve info history of a given account." }

sub args_desc { [
                 'user' => "The username of the account whose infohistory to retrieve.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "finduser", "infohistory");
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes exactly one argument. Consult the reference.")
        unless $user && !@args;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;

    my $infohistory = LJ::User::InfoHistory->get($u);

    return $self->error("No matches.")
        unless @$infohistory;

    $self->info("Infohistory of user: $user");
    foreach my $record (@$infohistory) {
        my $oldvalue = $record->oldvalue || '(none)';

        $self->info( "Changed " . $record->what .
            " at " . $record->timechange . "." );
        $self->info("Old value of " . $record->what . " was $oldvalue.");

        if ( my $other = $record->other ) {
            $self->info("Other information recorded: $other");
        }
    }

    return 1;
}

1;
