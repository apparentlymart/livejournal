#!/usr/bin/perl

# DSMS Message object
#
# internal fields:
#
#    to:         arrayref of MSISDNs of msg recipients
#    subject:    text subject for message
#    body_text:  text body of message
#    valid_for:  msg validity length in seconds
#    

package DSMS::Message;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(to subject body_text valid_for)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;


    # FIXME: should a lot of this checking be moved
    #        to the DSMS::Provider's ->send method?

    {
        croak "no recipients specified"
            unless $self->{to};

        if (ref $self->{to}) {
            croak "to arguments must be scalar or arrayref"
                if ref $self->{to} ne 'ARRAY';
        } else {
            $self->{to} = [ $self->{to} ];
        }
        croak "empty recipient list"
            unless scalar @{$self->{to}};

        foreach my $msisdn (@{$self->{to}}) {
            $msisdn =~ s/[\s\-]+//g;
            croak "invalid recipient: $msisdn"
                unless $msisdn =~ /^\+\d+$/;
        }
    }

    # FIXME: length requirements?
    $self->{subject}   .= '';
    $self->{body_text} .= '';
    croak "no body text specified"
        unless length $self->{body_text};

    if ($self->{valid_for} && $self->{valid_for} =~ /\D/) {
        croak "valid_for must be an integer number of seconds";
    }
    $self->{valid_for} += 0;

    return bless $self;
}

# generic getter/setter
sub _get {
    my DSMS::Message $self = shift;
    my ($f, $v) = @_;
    croak "invalid field: $f" 
        unless exists $self->{$f};

    return $self->{$f} = $v if defined $v;
    return $self->{$f};
}


sub to        { _get($_[0], 'to',        $_[1]) }
sub subject   { _get($_[0], 'subject',   $_[1]) }
sub body_text { _get($_[0], 'body_text', $_[1]) }
sub valid_for { _get($_[0], 'valid_for', $_[1]) }

1;
