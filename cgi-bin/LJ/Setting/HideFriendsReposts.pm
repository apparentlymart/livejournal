package LJ::Setting::HideFriendsReposts;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return LJ::is_enabled("hide_friends_reposts") && $u ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "hide_friends_reposts";
}

sub label {
    my $class = shift;

    return $class->ml('setting.hidefriendsreposts.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $hidefriendsreposts = $class->get_arg($args, 'hidefriendsreposts') || $u->prop('hidefriendsreposts');

    my $ret = LJ::html_check({
        name     => "${key}hidefriendsreposts",
        id       => "${key}hidefriendsreposts",
        value    => 1,
        selected => $hidefriendsreposts ? 1 : 0,
    });

    $ret .= " <label for='${key}hidefriendsreposts'>";
    $ret .= $class->ml('setting.hidefriendsreposts.option.comm');
    $ret .= "</label>";

    my $errdiv = $class->errdiv($errs, 'hidefriendsreposts');
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, 'hidefriendsreposts') ? 1 : 0;

    $u->set_prop('hidefriendsreposts', $val);

    return 1;
}

1;
