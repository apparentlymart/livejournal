package LJ::NotificationMethod::SMS;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';
use Class::Autouse qw(LJ::SMS);

sub can_digest { 0 };

# positional parameters: ->new($u, $event1, $event2, ...)
sub new {
    my $class = shift;
    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { 'SMS Notification' }

sub new_from_subscription {
    my $class = shift;
    my $subs = shift;

    return $class->new($subs->owner);
}

sub u {
    my $self = shift;
    croak "'u' is an object method"
        unless ref $self eq __PACKAGE__;

    if (my $u = shift) {
        croak "invalid 'u' passed to setter"
            unless LJ::isu($u);

        $self->{u} = $u;
    }
    croak "superfluous extra parameters"
        if @_;

    return $self->{u};
}

# notify a single event
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    my $u = $self->u;

    croak "'notify' requires an event"
        unless @_;

    my $ev = shift;
        croak "invalid event passed"
            unless ref $ev;

    croak "SMS can only accept one event at a time"
        if @_;

    my $sms_obj = LJ::SMS->new
        ( to   => $u,
          text => $ev->as_sms );
    $sms_obj->send;

}

sub configured {
    my $class = shift;

    # FIXME: should probably have more checks
    return LJ::SMS->configured ? 1 : 0;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;

    return LJ::SMS::configured_for_user($u) ? 1 : 0;
}

1;
