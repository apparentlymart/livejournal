package LJ::Event::InvitedFriendJoins;
use strict;
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $friendu) = @_;
    foreach ($u, $friendu) {
        croak 'Not an LJ::User' unless LJ::isu($_);
    }

    return $class->SUPER::new($u, $friendu->{userid});
}

sub is_common { 0 }

sub zero_journalid_subs_means { "friends" }

sub as_email_subject {
    my ($self, $u) = @_;
    return sprintf "$LJ::SITENAMESHORT Notices: %s has created a journal!", $self->friend->user;
}

sub as_email_string {
    my ($self, $u) = @_;
    my $u1 = LJ::load_userid($self->arg1);

    return '' unless $u && $u1;

    my $email = sprintf "Hi %s,

%s has created a new journal!", $u->display_username, $u1->display_username;

    unless (LJ::is_friend($u, $u1)) {
        $email .= sprintf "

If you want, you can add your friend to your friends list so you can stay up-to-date on the happenings in their life.

Click here to add them as your friend:
%s", "$LJ::SITEROOT/friends/add.bml?user=" . $u1->user;
    }

    $email .= "

To view your friend's profile
" . $u1->profile_url;
}

sub as_email_html {
    my ($self, $u) = @_;
    my $u1 = LJ::load_userid($self->arg1);

    return '' unless $u && $u1;

    my $email = sprintf "Hi %s,

%s has created a new journal!", $u->display_username, $u1->display_username;

    unless (LJ::is_friend($u, $u1)) {
        $email .= sprintf "

If you want, you can add your friend to your friends list so you can stay up-to-date on the happenings in their life.

Click here to add them as your friend:
%s", "<a href='$LJ::SITEROOT/friends/add.bml?user=" . $u1->user . "'>$LJ::SITEROOT/friends/add.bml?user=" . $u1->user . '</a>';
    }

    $email .= "

To view your friend's profile
<a href='" . $u1->profile_url . "'>" . $u1->profile_url . '</a>';
}

sub as_html {
    my $self = shift;
    my $u1 = LJ::load_userid($self->arg1);

    return 'A friend you invited has created a journal.' unless $u1;

    return sprintf(qq {
        A friend you invited has created the journal %s.
        },
                   $u1->ljuser_display,
                   );
}

sub as_string {
    my $self = shift;
    my $u1 = LJ::load_userid($self->arg1);

    return 'A friend you invited has created a journal.' unless $u1;

    return sprintf(qq {
        A friend you invited has created the journal %s.
        },
                   $u1->display_username,
                   );
}

sub as_sms {
    my $self = shift;
    return $self->as_string;
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    return "Someone I invited creates a new journal";
}

sub content { '' }

1;
