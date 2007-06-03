package LJ::Event::PollVote;
use strict;
use base 'LJ::Event';
use Class::Autouse qw(LJ::Poll);
use Carp qw(croak);

# we need to specify 'owner' here, because subscriptions are tied
# to the *poster*, not the journal, and we want to fire to the right
# person. we could divine this information from the poll itself,
# but it quickly becomes complicated.
sub new {
    my ($class, $owner, $voter, $poll) = @_;
    croak "No poll owner" unless $owner;
    croak "No poll!" unless $poll;
    croak "No voter!" unless $voter && LJ::isu($voter);

    return $class->SUPER::new($owner, $voter->userid, $poll->id);
}

## some utility methods
sub voter {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub poll {
    my $self = shift;
    return LJ::Poll->new($self->arg2);
}

sub entry {
    my $self = shift;
    return $self->poll->entry;
}

sub pollname {
    my $self = shift;
    my $poll = $self->poll;
    my $name = $poll->name;

    return sprintf("Poll #%d", $poll->id) unless $name;

    LJ::Poll->clean_poll(\$name);
    return sprintf("Poll #%d (\"%s\")", $poll->id, $name);
}

## notification methods

sub as_string {
    my $self = shift;
    return sprintf("%s has voted in %s",
                   $self->voter->display_username, $self->pollname);
}

sub as_html {
    my $self = shift;
    my $voter = $self->voter;
    my $poll = $self->poll;

    return sprintf("%s has voted in a deleted poll", $voter->ljuser_display)
        unless $poll && $poll->valid;

    return sprintf("%s has voted <a href='%s'>in %s</a>",
                   $voter->ljuser_display, $poll->url, $self->pollname);
}

sub as_email_subject {
    my $self = shift;
    return sprintf("%s voted in a poll!", $self->voter->display_username);
}


sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->display_username;
    my $voter = $self->voter->display_username;
    my $url = $self->poll->url;
    my $pollname = $self->pollname;

    my $email = "Hi $username,

$voter has replied to $pollname.

You can:

  - View the poll's status
    $url";

    return $email;
}


sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $voter = $self->voter->ljuser_display;
    my $url = $self->poll->url;
    my $pollname = $self->pollname;

    my $email = "Hi $username,

$voter has replied to $pollname.

You can:<ul>";

    $email .= "<li><a href=\"$url\">View the poll's status</a></li></ul>";

    return $email;
}

sub content { '' }

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $pollid = $subscr->arg1;
    return "Someone votes in a poll I posted" unless $pollid;

    return "Someone votes in poll #$pollid";
}

# only users with the track_pollvotes cap can use this
sub available_for_user  {
    my ($class, $u, $subscr) = @_;
    return $u->get_cap("track_pollvotes") ? 1 : 0;
}

1;
