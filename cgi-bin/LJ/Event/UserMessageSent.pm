package LJ::Event::UserMessageSent;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';
use LJ::Message;

sub new {
    my ($class, $u, $msgid) = @_;
    foreach ($u) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    return $class->SUPER::new($u, $msgid);
}

# TODO Should this return 1?
sub is_common { 1 }

sub load_message {
    my ($self) = @_;

    my $msg = LJ::Message::load($self->arg1, $self->u->{userid});
    return $msg;
}

sub as_html {
    my $self = shift;

    my $other_u = $self->load_message->other_u;
    return sprintf("message sent to %s.",
                   $other_u->ljuser_display);
}

sub as_string {
    my $self = shift;

    my $other_u = $self->load_message->other_u;
    return sprintf("message sent to %s.",
                   $other_u->{user});
}

sub subscription_as_html {''}

sub content { '' }

# override parent class sbuscriptions method to always return
# a subscription object for the user
sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;
    return unless ( $cid == $u->clusterid );

    my $row = { userid  => $self->u->{userid},
                ntypeid => '4', # Inbox
              };

    push @subs, LJ::Subscription->new_from_row($row);

    return @subs;
}

sub get_subscriptions {
    my ($self, $u, $subid) = @_;

    unless ($subid) {
        my $row = { userid  => $u->{userid},
                    ntypeid => '4', # Inbox
                  };

        return LJ::Subscription->new_from_row($row);
    }

}

# Have notifications for this event show up as read
sub mark_read {
    my $self = shift;
    return 1;
}

1;
