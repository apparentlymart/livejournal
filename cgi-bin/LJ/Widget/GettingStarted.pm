package LJ::Widget::GettingStarted;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    return "" unless $remote;

    # do we really even want to render this?
    return "" unless $class->should_render($remote);

    # epoch -> pretty
    my $date_format = sub {
        my $epoch = shift;
        my $exp = $epoch ? DateTime->from_epoch( epoch => $epoch ) : "";
        return $exp ? $exp->date() : "";
    };

    my $ret = "<h2>" . $class->ml('.widget.gettingstarted.title') . "</h2>";

    unless ($remote->postreg_completed) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.profile.note') . "<br />";
        $ret .= "&raquo; <a href='$LJ::SITEROOT/postreg/'>" . $class->ml('.widget.gettingstarted.profile.link') . "</a></p>";
    }

    unless ($class->has_enough_friends($remote)) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.friends.note', {'num' => $remote->friends_added_count}) . "<br />";
        $ret .= "&raquo; <a href='$LJ::SITEROOT/postreg/find.bml'>" . $class->ml('.widget.gettingstarted.friends.link') . "</a></p>";
    }

    if ($remote->number_of_posted_posts < 1) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.entry.note') . "<br />";
        $ret .= "&raquo; <a href='$LJ::SITEROOT/update.bml'>" . $class->ml('.widget.gettingstarted.entry.link') . "</a></p>";
    }

    if ($remote->get_userpic_count < 1) {
        $ret .= "<p>" . $class->ml('.widget.gettingstarted.userpics.note') . "<br />";
        $ret .= "&raquo; <a href='$LJ::SITEROOT/editpics.bml'>" . $class->ml('.widget.gettingstarted.userpics.link') . "</a></p>";
    }

    $ret .= "<p>" . LJ::name_caps($remote->{caps});
    if ($remote->in_class('paid') && !$remote->in_class('perm')) {
        my $exp_epoch = LJ::Pay::get_account_exp($remote);
        my $exp = $date_format->($exp_epoch);
        $ret .= " (<a href='$LJ::SITEROOT/manage/payments/'>" . $class->ml('.widget.gettingstarted.expires', {'date' => $exp}) . "</a>)"
            if $exp;
    }
    $ret .= "</p>";
    $ret .= "<p><a href='$LJ::SITEROOT/manage/'>" . $class->ml('.widget.gettingstarted.manage') . "</a></p>";

    return $ret;
}

sub should_render {
    my $class = shift;

    my $remote = LJ::get_remote();
    return 0 unless $remote;

    return 1 unless $remote->postreg_completed;
    return 1 unless $class->has_enough_friends($remote);

    return 1 unless $remote->number_of_posted_posts > 0;
    return 1 unless $remote->get_userpic_count > 0;

    return 0;
}

# helper functions used within this widget, but don't
# make a lot of sense out of context

sub has_enough_friends {
    my $self = shift;
    my $u = shift;

    # need 4 friends for us to stop bugging them
    return $u->friends_added_count < 4 ? 0 : 1;
}

1;
