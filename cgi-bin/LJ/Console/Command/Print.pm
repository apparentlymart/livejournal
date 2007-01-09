# Base class for LJ::Console commands

package LJ::Console::Command::Print;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd {
    my $self = shift;
    return "print";
}

sub desc {
    my $self = shift;
    return "This is a debugging function.  Given an arbitrary number of meaningless arguments, it'll print each one back to you.  If an argument begins with a bang (!) then it'll be printed to the error stream instead.";
}

sub args_desc {
    my $self = shift;
    return [];
}

sub usage {
    my $self = shift;
    return '...';
}

sub can_execute {
    my $self = shift;
    return 1;
}

sub execute {
    my $self = shift;

    my @resp = ();

    my $remote = $self->remote;
    push @resp, LJ::Console::Response->new
        ( status => 'info',
          text   => "welcome to 'print', " . $remote->user, );

    foreach my $arg ($self->args) {
        my $status = $arg =~ /^\!// ? 'success' : 'error';

        push @resp, LJ::Console::Response->new
            ( status => $status,
              text   => $arg );
    }

    return @resp;
}

1;
