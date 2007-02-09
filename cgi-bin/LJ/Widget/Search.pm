package LJ::Widget::Search;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my @search_opts = (
        'int' => $class->ml('widget.search.interest'),
        'user' => $class->ml('widget.search.username'),
        'email' => $class->ml('widget.search.email'),
        'aolim' => $class->ml('widget.search.aim'),
        'icq' => $class->ml('widget.search.icq'),
        'jabber' => $class->ml('widget.search.jabber'),
        'msn' => $class->ml('widget.search.msn'),
        'yahoo' => $class->ml('widget.search.yahoo'),
    );

    $ret .= "<h1>" . $class->ml('widget.search.title') . "</h1>";
    $ret .= "<form action='$LJ::SITEROOT/multisearch.bml' method='post'>";
    $ret .= LJ::html_select({name => 'type', selected => 'int'}, @search_opts) . " ";
    $ret .= LJ::html_text({name => 'q', 'size' => 30}) . " ";
    $ret .= LJ::html_submit($class->ml('widget.search.submit'));
    $ret .= "</form>";

    return $ret;
}

1;
