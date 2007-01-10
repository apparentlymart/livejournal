# Base class for LJ::Console commands

package LJ::Console::Command;

use strict;
use Carp qw(croak);
use LJ::Console::Response;

sub new {
    my $class = shift;
    my %opts = @_;

    my $self = {
        command => delete $opts{command},
        args    => delete $opts{args} || [],
        output  => [],
    };

    # args can be arrayref, or just one arg
    if ($self->{args} && ! ref $self->{args}) {
        $self->{args} = [ $self->{args} ];
    }
    croak "invalid argument: args"
        if $self->{args} && ! ref $self->{args} eq 'ARRAY';

    croak "invalid parameters: ", join(",", keys %opts)
        if %opts;

    return bless $self, $class;
}

sub args {
    my $self = shift;
    return @{$self->{args}||[]};
}

sub command { $_[0]->cmd }
sub cmd {
    my $self = shift;
    die "cmd not implemented in $self";
}

sub desc {
    my $self = shift;
    return "";
}

sub usage {
    my $self = shift;
    return "";
}

sub args_desc {
    my $self = shift;

    # [ arg1 => 'desc', arg2 => 'desc' ]
    return [];
}

sub can_execute {
    my $self = shift;
    return 0;
}

# return 1 on success.  on failure, return 0 or die.  (will be caught)
sub execute {
    my $self = shift;
    die "execute not implemented in $self";
}

sub execute_safely {
    my $cmd = shift;
    eval {
        if ($cmd->can_execute) {
            unless ($cmd->execute($cmd->args)) {
                $cmd->error("Command " . $cmd->command . "' didn't return success.");
            }
        } else {
            $cmd->error("You are not authorized to do this");
        }
    };

    if ($@) {
        $cmd->error("Died executing '" . $cmd->command . "': $@");
    }

    return 1;
}

sub responses {
    my $self;
    return @{$self->{output} || []};
}

sub print {
    my $self = shift;
    my $text = shift;
    push @{$self->{output}}, LJ::Console::Response->new( status => 'success', text => $text );
}

sub error {
    my $self = shift;
    my $text = shift;

    push @{$self->{output}}, LJ::Console::Response->new( status => 'error', text => $text );
}

sub info {
    my $self = shift;
    my $text = shift;

    push @{$self->{output}}, LJ::Console::Response->new( status => 'info', text => $text );
}

1;
