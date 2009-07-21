package LJ::Widget::CategorySummary;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Browse );

sub need_res { qw( stc/widgets/categorysummary.css js/widgets/categorysummary.js) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $category = $opts{category};
    die "Invalid browse object passed to widget." unless $category;

    my @subs = $category->children;
    @subs = sort { lc $a->display_name cmp lc $b->display_name } @subs;
    my $subcats = join(" | ", map { "<a href='" . $_->url . "'>" . $_->display_name . "</a>" } @subs);

    my @topsubs = $category->top_children;
    @topsubs = sort { lc $a->display_name cmp lc $b->display_name } @topsubs;
    my $topcats = join(" | ", map { "<a href='" . $_->url . "'>" . $_->display_name . "</a>" } @topsubs);

    my $ret;

    $ret .= "<div class='catsummary-outer'>\n";

    $ret .= "<h2>";
    $ret .= "<div class='expand'><span class='control grow'>[:) </span></div>" if $topcats;
    $ret .= "<a href='" . $category->url . "'>";
    $ret .= "<span class='catsummary-categoryname'>" . $category->display_name . "</span></a>";
    $ret .= "</h2>\n";

    $ret .= "<div class='catsummary-inner'>";

    if ($subcats) {
        $ret .= "<p class='catsummary-subcats' style='display:none'>$subcats</p>";
    }

    if ($topcats) {
        $ret .= "<p class='catsummary-topcats'>$topcats</p>";
    }

    $ret .= "</div></div>\n";

    return $ret;
}

1;
