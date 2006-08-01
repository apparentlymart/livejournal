#!/usr/bin/perl

# DSMS Message object
#
# internal fields:
#
#    to:         arrayref of MSISDNs of msg recipients
#    subject:    text subject for message
#    body_text:  decoded text body of message
#    body_raw:   raw text body of message
#    type:       'incoming' or 'outgoing'
#    meta:       hashref of metadata key/value pairs
#    

package DSMS::Message;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(to from subject body_text body_raw type meta)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;


    # FIXME: should a lot of this checking be moved
    #        to the DSMS::Provider's ->send method?

    {
        croak "no from address specified"
            unless $self->{from};

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

        foreach my $msisdn (@{$self->{to}}, $self->{from}) {
            $msisdn =~ s/[\s\-]+//g;
            croak "invalid recipient: $msisdn"
                unless $msisdn =~ /^(?:\+\d+|\d{5})$/;
        }

        croak "invalid type argument"
            unless $self->{type} =~ /^(?:incoming|outgoing)$/;

        croak "invalid meta argument"
            if $self->{meta} && ref $self->{meta} ne 'HASH';

        $self->{meta} ||= {};
    }

    # FIXME: length requirements?
    $self->{subject}   .= '';
    $self->{body_text} .= '';
    $self->{body_raw} = $self->{body_text} unless defined $self->{body_raw};

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
sub from      { _get($_[0], 'from',      $_[1]) }
sub subject   { _get($_[0], 'subject',   $_[1]) }
sub body_text { _get($_[0], 'body_text', $_[1]) }
sub body_raw  { _get($_[0], 'body_raw',  $_[1]) }
sub type      { _get($_[0], 'type',      $_[1]) }
sub meta      { _get($_[0], 'meta',      $_[1]) }

sub is_incoming {
    my DSMS::Message $self = shift;
    return $self->type eq 'incoming' ? 1 : 0;
}

sub is_outgoing {
    my DSMS::Message $self = shift;
    return $self->type eq 'outgoing' ? 1 : 0;
}

1;
