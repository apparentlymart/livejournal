package LJ::Setting::CommentsStyleMine;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return LJ::is_enabled("comments_style_mine") && $u && $u->is_personal ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentsstylemine.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $stylealwaysmine = $class->get_arg($args, "stylealwaysmine") || $u->opt_stylealwaysmine;
    my $commentsstylemine = $class->get_arg($args, "commentsstylemine") || $u->opt_commentsstylemine;
    my $can_use_commentsstylemine = $u->can_use_commentsstylemine? 1 : 0;

    $can_use_commentsstylemine = 0 if $stylealwaysmine;

    my $ret = LJ::html_check({
        name => "${key}commentsstylemine",
        id => "${key}commentsstylemine",
        value => 1,
        selected => $commentsstylemine && $can_use_commentsstylemine? 1 : 0,
        disabled => $can_use_commentsstylemine? 0 : 1,
    });

    $ret .= " <label for='${key}commentsstylemine'>" . $class->ml('setting.commentsstylemine.option') . "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "commentsstylemine") ? "Y" : "N";
    $u->set_prop( opt_commentsstylemine => $val );

    return 1;
}

1;
