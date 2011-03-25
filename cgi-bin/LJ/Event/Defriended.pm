package LJ::Event::Defriended;
use strict;
use Scalar::Util qw(blessed);
use Carp qw(croak);
use base 'LJ::Event';

sub new {
    my ($class, $u, $fromu) = @_;

    my $uid      = LJ::want_userid($u); ## friendid
    my $fromuid  = LJ::want_userid($fromu);

    return $class->SUPER::new($uid, $fromuid);
}

sub is_common { 0 }

my @_ml_strings_en = (
    'esn.public',                   # 'public',
    'esn.defriended.subject',       # '[[who]] removed you from their Friends list',
    'esn.remove_friend',            # '[[openlink]]Remove [[postername]] from your Friends list[[closelink]]',
    'esn.post_entry',               # '[[openlink]]Post an entry[[closelink]]',
    'esn.edit_friends',             # '[[openlink]]Edit Friends[[closelink]]',
    'esn.edit_groups',              # '[[openlink]]Edit Friends groups[[closelink]]',
    'esn.defriended.alert',         # '[[who]] removed you from their Friends list.',
    'esn.defriended.email_text',    # 'Hi [[user]],
                                    #
                                    #[[poster]] has removed you from their Friends list.
                                    #
                                    #You can:',
);

sub as_email_subject {
    my ($self, $u) = @_;

    return LJ::Lang::get_text($u->prop('browselang'), 'esn.defriended.subject', undef, { who => $self->friend->display_username } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    my $lang        = $u->prop('browselang');
    my $user        = $is_html ? ($u->ljuser_display) : ($u->user);
    my $poster      = $is_html ? ($self->friend->ljuser_display) : ($self->friend->user);
    my $postername  = $self->friend->user;
    my $journal_url = $self->friend->journal_base;
    my $journal_profile = $self->friend->profile_url;

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings_en);

    my $entries = LJ::is_friend($u, $self->friend) ? "" : " " . LJ::Lang::get_text($lang, 'esn.public', undef);

    my $vars = {
        who         => $self->friend->display_username,
        poster      => $poster,
        postername  => $postername,
        user        => $user,
        entries     => $entries,
    };

    return LJ::Lang::get_text($lang, 'esn.defriended.email_text', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.remove_friend' => [ LJ::is_friend($u, $self->friend) ? 1 : 0,
                                            "$LJ::SITEROOT/friends/add.bml?user=$postername" ],
            'esn.post_entry'    => [ 3, "$LJ::SITEROOT/update.bml" ],
            'esn.edit_friends'  => [ 4, "$LJ::SITEROOT/friends/edit.bml" ],
            'esn.edit_groups'   => [ 5, "$LJ::SITEROOT/friends/editgroups.bml" ],
        }
    );
}

sub as_email_string {
    my ($self, $u) = @_;
    return _as_email($self, $u, 0);
}

sub as_email_html {
    my ($self, $u) = @_;
    return _as_email($self, $u, 1);
}

# technically "former friend-of", but who's keeping track.
sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}

sub as_html {
    my $self = shift;
    return sprintf("%s has removed you from their Friends list.",
                   $self->friend->ljuser_display);
}

sub as_html_actions {
    my ($self) = @_;

    my $u = $self->u;
    my $friend = $self->friend;
    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $friend->addfriend_url . "'>Remove friend</a>"
        if LJ::is_friend($u, $friend);
    $ret .= " <a href='" . $friend->profile_url . "'>View profile</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my ($self, $u, $opt) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;

    my $tinyurl = "http://m.livejournal.com/read/user/".$self->friend->{user};
    my $mparms = $opt->{mobile_url_extra_params};
    $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
    $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
    undef $tinyurl if $tinyurl =~ /^500/;
    
# [[friend]] has removed you from their Friends list.
    return LJ::Lang::get_text($lang, 'notification.sms.defriended', undef, {
        friend     => $self->friend->{user},
        mobile_url => $tinyurl,
    });

#    return sprintf("%s has removed you from their Friends list.",
#                   $self->friend->{user});
}

sub as_alert {
    my $self = shift;
    my $u = shift;
    my $friend = $self->friend;
    return '' unless $friend;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.defriended.alert', undef, { who => $friend->ljuser_display() });
}

sub subscription_as_html {
    my ($class, $subscr) = @_;
    my $journal = $subscr->journal or croak "No user";
    my $journal_is_owner = LJ::u_equals($journal, $subscr->owner);
    # "Someone removes $user from their Friends list"
    # where $user may be also 'me'.
    return LJ::Lang::ml('event.defriended.' . ($journal_is_owner ? 'me' : 'user'), { user => $journal->ljuser_display });
}

sub content {
    my ($self) = @_;

    return $self->as_html_actions;
}

sub available_for_user  {
    my ($self, $u) = @_;

    return 0 if $self->userid != $u->id;
    return $u->get_cap("track_defriended") ? 1 : 0;
}

sub is_subscription_visible_to  {
    my ($self, $u) = @_;

    return $self->userid != $u->id ? 0 : 1;
}

sub is_tracking { 0 }

1;
