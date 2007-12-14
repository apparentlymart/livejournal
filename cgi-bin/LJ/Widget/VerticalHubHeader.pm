package LJ::Widget::VerticalHubHeader;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical );

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $ret;

    # multiple parents can be defined, but just use the first one for the nav
    my @parents = $vertical->parents;
    my $parent = $parents[0];

    $ret .= "<h1>";
    if ($parent) {
        $ret .= "<a href='" . $parent->url . "'><strong>" . $parent->display_name . "</strong></a> &gt; ";
    }
    $ret .= $vertical->display_name . "</h1>";

    my (@children, @siblings);
    foreach my $child ($vertical->children) {
        push @children, "<a href='" . $child->url . "'>" . $child->display_name . "</a>";
    }
    foreach my $sibling ($vertical->siblings( include_self => 1 )) {
        my $el;
        if ($sibling->equals($vertical)) {
            $el .= "<strong>";
        } else {
            $el .= "<a href='" . $sibling->url . "'>";
        }
        $el .= $sibling->display_name;
        if ($sibling->equals($vertical)) {
            $el .= "</strong>";
        } else {
            $el .= "</a>";
        }

        push @siblings, $el;
    }
    $ret .= "<p class='children'>" . join(" | ", @children) . "</p>" if @children;
    $ret .= "<p class='siblings'>" . join(" | ", @siblings) . "</p>" if @siblings;

    return $ret;
}

1;
