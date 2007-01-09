# Base class for LJ::Console commands

package LJ::Console::Command;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my %opts = @_;

    my $self = {
        remote => delete $opts{remote}, 
        args   => delete $opts{args} || [], 
    };

    croak "invalid argument: remote"
        unless LJ::isu($self->{remote});

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

sub remote {
    my $self = shift;
    return $self->{remote};
}

sub args {
    my $self = shift;
    return @{$self->{args}||[]};
}

sub cmd {
    my $self = shift;
    return "";
}

sub desc {
    my $self = shift;
    return "";
}

sub usage {
    my $self = shift;
    return '';
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

sub execute {
    my $self = shift;
    return 1;
}

sub success_response {
    my $self = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'success', text => $text );
}

sub error_response {
    my $self = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'error', text => $text );
}

sub info_response {
    my $self = shift;
    my $text = shift;

    return LJ::Console::Response->new( status => 'info', text => $text );
}

1;
