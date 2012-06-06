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

my @_ml_strings = (
    'esn.invited_friend_joins.subject',         # '[[who]] created a journal!'
    'esn.add_friend',                           # '[[openlink]]Add [[journal]] to your Friends list[[closelink]]',
    'esn.read_journal',                         # '[[openlink]]Read [[postername]]\'s journal[[closelink]]',
    'esn.view_profile',                         # '[[openlink]]View [[postername]]\'s profile[[closelink]]',
    'esn.invite_another_friend',                # '[[openlink]]Invite another friend[[closelink]]',
    'esn.invited_friend_joins.alert.unnamed',   # 'A friend you invited has created a journal.'
    'esn.invited_friend_joins.alert',           # 'A friend you invited has created the journal [[newuser]]',
    'esn.invited_friend_joins.email',           # 'Hi [[user]],
                                                #
                                                # Your friend [[newuser]] has created a journal on [[sitenameshort]]!
                                                #
                                                # You can:'
);

sub as_email_subject {
    my ($self, $u) = @_;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.invited_friend_joins.subject', undef,
        { who => $self->friend->display_username } );
}

sub _as_email {
    my ($self, $u, $is_html) = @_;

    return '' unless $u && $self->friend;

    my $lang            = $u->prop('browselang');
    my $user            = $is_html ? $u->ljuser_display : $u->display_username;
    my $newusername     = $self->friend->display_username;
    my $newuser         = $is_html ? $self->friend->ljuser_display : $newusername;
    my $newuser_url     = $self->friend->journal_base;
    my $newuser_profile = $self->friend->profile_url;

    # Precache text lines
    LJ::Lang::get_text_multi($lang, undef, \@_ml_strings);

    my $vars = {
            user            => $user,
            who             => $newuser,
            newuser         => $newuser,
            postername      => $newusername,
            journal         => $newusername,
            sitenameshort   => $LJ::SITENAMESHORT,
    };

    return LJ::Lang::get_text($lang, 'esn.invited_friend_joins.email', undef, $vars) .
        $self->format_options($is_html, $lang, $vars,
        {
            'esn.add_friend'            => [ 1, "$LJ::SITEROOT/friends/add.bml?user=$newusername" ], # Why not $self->friend->addfriend_url ?
            'esn.read_journal'          => [ 2, $newuser_url ],
            'esn.view_profile'          => [ 3, $newuser_profile ],
            'esn.invite_another_friend' => [ 4, "$LJ::SITEROOT/friends/invite.bml" ],
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

sub as_html {
    my $self = shift;

    return 'A friend you invited has created a journal.'
        unless $self->friend;

    return sprintf "A friend you invited has created the journal %s", $self->friend->ljuser_display;
}

sub as_html_actions {
    my ($self) = @_;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $self->friend->journal_base . "'>View Journal</a>";
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my ($self, $u, $opt) = @_;
    my $lang = ($u && $u->prop('browselang')) || $LJ::DEFAULT_LANG;
    
    my $tinyurl;
    if( $self->friend->user ){
        $tinyurl = "http://m.livejournal.com/read/user/".$self->friend->user;
        my $mparms = $opt->{mobile_url_extra_params};
        $tinyurl .= '?' . join('&', map {$_ . '=' . $mparms->{$_}} keys %$mparms) if $mparms;
        $tinyurl = LJ::Client::BitLy->shorten($tinyurl);
        undef $tinyurl if $tinyurl =~ /^500/;
    }
    
    my $mlstring = $self->friend ? 'notification.sms.invitedfriendjoins' : 'notification.sms.invitedfriendjoins_uknown';
# A friend you invited has created a journal.
# A friend you invited has created the journal [[friend]]
    return LJ::Lang::get_text($lang, $mlstring, undef, {
        friend     => $self->friend->user,
        mobile_url => $tinyurl,
    });

}

sub as_alert {
    my $self = shift;
    my $u = shift;
    my $friend = $self->friend;
    return LJ::Lang::get_text($u->prop('browselang'),
        'esn.invited_friend_joins.alert' . ($friend ? '' : '.unnamed'), undef,
        $friend ? { newuser => $friend->ljuser_display() } : {} );
}

sub friend {
    my $self = shift;
    return LJ::load_userid($self->arg1);
}


sub subscription_as_html {
    my ($class, $subscr) = @_;
    return LJ::Lang::ml('event.invited_friend_joins'); # "Someone I invited creates a new journal";
}

sub content {
    my ($self, $target) = @_;

    return $self->as_html_actions;
}

sub available_for_user  { 1 }
sub is_subscription_visible_to  { 1 }
sub is_tracking { 0 }

sub as_push {
    my $self = shift;
    my $u = shift;
    my $lang = shift;

    return LJ::Lang::get_text($lang, "esn.push.notification.invitedfriendjoins", 1, {
        journal => $self->friend->user,
    })
}

sub as_push_payload {
    my $self = shift;
    my $lang = shift;

    return '"t":13,"j":"'.$self->friend->user.'"';
}

1;
