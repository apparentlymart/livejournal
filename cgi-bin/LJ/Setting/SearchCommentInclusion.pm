package LJ::Setting::SearchCommentInclusion;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u ? 1 : 0;
}

=head
sub helpurl {
    my ($class, $u) = @_;

    return "search_engines";
}
=cut

sub label {
    my ($class, $u) = @_;

    return $class->ml('setting.searchcommentinclusion.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $searchcommentinclusion = $class->get_arg($args, "searchcommentinclusion") || $u->prop("user_comment_no_index");

    my $ret = LJ::html_check({
        name => "${key}searchcommentinclusion",
        id => "${key}searchcommentinclusion",
        value => 1,
        selected => $searchcommentinclusion ? 1 : 0,
    });
    $ret .= " <label for='${key}searchcommentinclusion'>";
    $ret .= $class->ml('setting.searchcommentinclusion.option.self');
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "searchcommentinclusion") ? 1 : 0;
    $u->set_prop( user_comment_no_index => $val );

    return 1;
}

1;
