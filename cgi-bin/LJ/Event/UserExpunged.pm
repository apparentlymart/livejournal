package LJ::Event::UserExpunged;
use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ($class, $u) = @_;
    croak "No $u" unless $u;

    return $class->SUPER::new($u);
}

sub as_string {
    my ($self, $u) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

# [[journal]] has been purged.
    return LJ::Lang::get_text($lang, 'notification.sms.userexpunged', undef, {
        journal => $self->event_journal->display_username(1),
    });    
}

sub as_alert {
    my $self = shift;
    my $u = shift;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.purged.alert', undef, { journal => $self->event_journal->ljuser_display() });
}

sub as_html {
    my $self = shift;
    return $self->event_journal->ljuser_display . " has been purged.";
}

sub as_html_actions {
    my $self = shift;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='$LJ::SITEROOT/rename/'>Rename my account</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->display_username;
    my $purgedname = $self->event_journal->display_username;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:

  - Rename your account
    $LJ::SITEROOT/rename/};

    return $email;
}

sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $purgedname = $self->event_journal->ljuser_display;

    my $email = qq {Hi $username,

Another set of deleted accounts have just been purged, and the username "$purgedname" is now available.

You can:<ul>};

    $email .= "<li><a href='$LJ::SITEROOT/rename/'>Rename your account</a></li>";
    $email .= "</ul>";

    return $email;
}

sub as_email_subject {
    my $self = shift;
    my $username = $self->event_journal->user;

    return sprintf "The username '$username' is now available!";
}

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return LJ::Lang::ml('event.user_expunged', { user => $ljuser }); # "$ljuser has been purged";
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

sub available_for_user  { 1 }
sub is_subscription_visible_to  { 1 }
sub is_tracking { 1 }

sub as_push {
    my ($self, $u, $lang) = @_;

    return LJ::Lang::get_text($lang, "esn.push.notification.eventtrackusernamepurged", 1, {
        user => $self->event_journal->user
    })
}

sub as_push_payload {
    my $self = shift;

    return { 't' => 24,
             'j' => $self->event_journal->user,
           };
}


1;
