package LJ::NotificationMethod::DebugLog;

use strict;
use Carp qw/ croak /;
use base 'LJ::NotificationMethod';
require "$ENV{LJHOME}/cgi-bin/weblib.pl";

sub can_digest { 1 };

# takes a $u
sub new {
    my $class = shift;

    croak "no args passed"
        unless @_;

    my $u = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    my $self = { u => $u };

    return bless $self, $class;
}

sub title { 'DebugLog' }

# send emails for events passed in
sub notify {
    my $self = shift;
    croak "'notify' is an object method"
        unless ref $self eq __PACKAGE__;

    my $u = $self->u;

    my @events = @_
        or croak "'notify' requires one or more events";

    foreach my $ev (@events) {

        # ......
    }

    return 1;
}

sub configured {
    my $class = shift;
    return 1;
}

sub configured_for_user {
    my $class = shift;
    my $u = shift;
    return 1;
}

############################################################################
# why do we need these: ?
############################################################################

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

1;
