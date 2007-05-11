package LJ::Event::Birthday;

use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ($class, $u) = @_;
    croak "No user" unless $u && LJ::isu($u);

    return $class->SUPER::new($u);
}

sub bdayuser {
    my $self = shift;
    return $self->event_journal;
}

sub as_string {
    my $self = shift;
    my $user = $self->bdayuser->display_username;

    return "It's $user\'s birthday!";
}

sub as_html {
    my $self = shift;
    my $user = $self->bdayuser->ljuser_display;

    return "It's $user\'s birthday!";
}

sub as_email_subject {
    my $self = shift;

    return sprintf("LiveJournal Notices: %s's birthday is coming up!",
                   $self->bdayuser->display_username);
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->user;
    my $bdayuser = $self->bdayuser->display_username;

    my $email = qq {Hi $username,

Today is $bdayuser\'s birthday!

You can:
  - Send them a virtual gift
    $LJ::SITEROOT/shop/view.bml?item=vgift
    };

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $bdayuser = $self->bdayuser->ljuser_display;

    my $email = qq {Hi $username,

Today is $bdayuser\'s birthday!

You can:<ul>};

    $email .= "<li><a href=\"$LJ::SITEROOT/shop/view.bml?item=vgift\">"
           . "Send them an additional virtual gift</a></li>";
    $email .= "</ul>";
    return $email;
}


sub zero_journalid_subs_means { "friends" }

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    return "It's one of my friends' birthdays."
        unless $journal;

    my $ljuser = $journal->ljuser_display;
    return "It's $ljuser\'s birthday";
}

sub content { '' }

1;
