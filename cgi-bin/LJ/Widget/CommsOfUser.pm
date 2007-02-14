package LJ::Widget::CommsOfUser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    return "" unless $opts{user};

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::load_user($opts{user});
    return "" unless $u;

    my $remote = LJ::get_remote();
    return "" if $u->id == $remote->id;

    my $max_comms = $opts{max_comms} || 3;
    my @notable_comms = $u->notable_communities($max_comms);
    return "" unless @notable_comms;

    $ret .= "<h1>" . $class->ml('widget.commsofuser.title', {user => $u->ljuser_display}) . "</h1>";
    $ret .= "<ul>";
    foreach my $comm (@notable_comms) {
        $ret .= "<li>" . $comm->ljuser_display . " - " . $comm->name_html  . "</li>";
    }
    $ret .= "</ul>";
    $ret .= "<p>&raquo; <a href='" . $u->profile_url . "'>" . $class->ml('widget.commsofuser.viewprofile', {user => $u->display_username}) . "</a></p>";

    return $ret;
}

1;
