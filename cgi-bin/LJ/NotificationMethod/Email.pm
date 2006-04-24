package LJ::NotificationMethod::Email;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';

sub can_digest { 1 };

# positional parameters: ->new($u, $event1, $event2, ...)
sub new {
    my $class = shift;
    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { 'Email' }

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

    my @events = @_;
    croak "'notify' requires one or more events"
        unless @events;

    foreach my $ev (@events) {
        croak "invalid event passed" unless ref $ev;

        LJ::send_mail({
            to       => $u->{email},
            from     => $LJ::BOGUS_EMAIL,
            fromname => $LJ::SITENAMESHORT,
            wrap => 1,
            charset => 'utf-8',
            subject => $ev->title,
            html    => , # FIXME: make this work!
            body    => $ev->as_string
        }) or die "unable to send notification email";
    }
}

1;
