#!/usr/bin/perl

# DSMS GatewayResponse object
#
# internal fields:
#
#    msg:        DSMS::Message object, or undef on error
#    is_success: Boolean success value of the response
#    error_str:  Error string if ! is_success
#    responder:  Response content callback
#    

package DSMS::GatewayResponse;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(msg is_success error_str responder)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;

    croak "invalid DSMS::Message object"
        unless ref $self->{msg} eq 'DSMS::Message';

    $self->{is_success} = $self->{is_success} ? 1 : 0;
    $self->{error_str} .= "";

    return bless $self;
}

sub is_error {
    my $self = shift;
    return ! $self->is_success;
}

sub send_response {
    my $self = shift;

    my $cb = $self->responder;
    die "invalid content callback"
        unless ref $cb eq 'CODE';

    return $cb->();
}

# generic getter/setter
sub _get {
    my $self = shift;
    my ($f, $v) = @_;
    croak "invalid field: $f" 
        unless exists $self->{$f};

    return $self->{$f} = $v if defined $v;
    return $self->{$f};
}

# accessors
sub msg        { _get($_[0], 'msg',        $_[1]) }
sub is_success { _get($_[0], 'is_success', $_[1]) }
sub error_str  { _get($_[0], 'error_str',  $_[1]) }
sub responder  { _get($_[0], 'responder',  $_[1]) }


1;
