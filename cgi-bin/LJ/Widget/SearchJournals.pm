package LJ::Widget::SearchJournals;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/widget-layout.css stc/widgets/search-journals.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= "<div class='w-head'><h2><span class='w-head-in'>" . $class->ml('widget.searchjournals.header') . "</span></h2><i class='w-head-corner'></i></div>";
    $ret .= "<div class='w-body'>";
    $ret .= "<div class='b-search-journals'>";
    $ret .= "<form action='$LJ::SITEROOT/search/' method='get'><fieldset><div class='search-item search-query'><table><tbody><tr>";
    $ret .= "<td width='60%'><label for='SearchText'></label><input type='search' value='' size='12' class='type-text' name='q' id='SearchText' /></td>";
    $ret .= "<input type='hidden' name='area' value='default'>";
    $ret .= "<td width='10%'><button type='submit'>" . BML::ml('horizon.search.submit') . "</button></td></tr></table></div></fieldset></form>";

    my $words;
    if ($opts{substitude_words}) {
        $words = $opts{substitude_words};
    } else {
        my $system = LJ::load_user('system') or die "No 'system' user in DB";
        $words = $system->prop('search_admin');
    }
    my @keywords = split /\s*\n+\s*/, $words;
    $ret .= "<ul class=i-cloud>";
    $ret .= join ' ', map { "<li><h3><a href='$LJ::SITEROOT/search/?q=" . LJ::eurl($_) . "&area=default'>" . LJ::ehtml($_) . "</a></h3></li>" } @keywords;
    $ret .= "</ul>";
    $ret .= "</div>";

    $ret .= "<div class='b-random-journal'>";
    $ret .= "<h3>" . $class->ml('widget.searchjournals.loggedout.random') . "</h3>";
    $ret .= "<form action='$LJ::SITEROOT/random.bml'>" . $class->html_submit($class->ml('widget.searchjournals.loggedout.random.button')) . "</form>";
    $ret .= "</div>";
    $ret .= "</div>";

    return $ret;
}

1;
