package LJ::Widget::Search;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/search.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my @search_opts = (
        'int' => $class->ml('.widget.search.interest'),
        'region' => $class->ml('.widget.search.region'),
        'user' => $class->ml('.widget.search.username'),
        'email' => $class->ml('.widget.search.email'),
        'aolim' => $class->ml('.widget.search.aim'),
        'icq' => $class->ml('.widget.search.icq'),
        'jabber' => $class->ml('.widget.search.jabber'),
        'msn' => $class->ml('.widget.search.msn'),
        'yahoo' => $class->ml('.widget.search.yahoo'),
    );

    $ret .= "<h2>" . $class->ml('.widget.search.title') . "</h2>\n";
    $ret .= "<form action='$LJ::SITEROOT/multisearch.bml' method='post'>\n";
    $ret .= LJ::html_select({name => 'type', selected => 'int', class => 'select'}, @search_opts) . " ";
    $ret .= LJ::html_text({name => 'q', 'class' => 'text', 'size' => 30}) . " ";
    $ret .= LJ::html_submit($class->ml('.widget.search.submit'));
    $ret .= "</form>";

    return $ret;
}

1;
