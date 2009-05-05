package LJ::Widget::CategoryFull;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Browse );

sub need_res { qw( stc/browse.css stc/widgets/categoryfull.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $cat = $opts{cat};
    my $title = $opts{title};
    die "Invalid browse object passed to widget." unless $cat;

    my $ret;

    $$title .= "<strong>" . $cat->display_name . "</strong>";
    $ret .= "<ul class='browsesubcat'>\n";

    foreach my $subcat ($cat->children) {
        $ret .= "<li><a href='" . $subcat->url . "'>&rsaquo; " .
                $subcat->display_name . "</a>\n";

        my @childs = $subcat->children;
        unless (@childs) {
            $ret .= "</li>\n";
            next;
        }

        $ret .= "<ul class='childcat'>\n";
        foreach my $child (@childs) {
            $ret .= "<li><a href='" . $child->url . "'>&raquo; " .
                    $child->display_name . "</a></li>\n";
        }
        $ret .= "</ul></li>\n";
    }

    $ret .= "</ul>\n";

    return $ret;
}

1;
