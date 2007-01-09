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
    return "This is a debugging function. Given any number of arguments, it'll print each one back to you. If an argument begins with a bang (!), then it'll be printed to the error stream instead.";
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
    push @resp, $self->info_response("Welcome to 'print', " . $remote->user,);

    foreach my $arg ($self->args) {
        if ($arg =~ /^\!/) {
            push @resp, $self->error_response($arg);
        } else {
            push @resp, $self->success_response($arg);
        }
    }

    return @resp;
}

1;
