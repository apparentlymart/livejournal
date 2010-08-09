package LJ::Identity::Jabber;
use strict;

sub typeid { 'J' }
sub pretty_type { 'Jabber' }
sub short_code { 'jabber' }
sub url { $LJ::SITEROOT }

sub initialize_user {
    # there's no initialization we need to do
}

sub display_name {
    my ($self, $u) = @_;
    return $u->username;
}

sub ljuser_display_params {
    my ($self, $u, $opts) = @_;

    return {
        'journal_url'  => $opts->{'journal_url'} || $self->url,
        'journal_name' => $u->display_name,
        'userhead'     => 'userinfo.gif',
        'userhead_w'   => 17,
    };
}

sub profile_window_title {
    return LJ::Lang::ml('/userinfo.bml.title.jabberprofile');
}

1;
