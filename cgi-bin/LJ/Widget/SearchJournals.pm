package LJ::Widget::SearchJournals;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

#sub need_res { qw( stc/widgets/examplerenderwidget.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= "<form action='$LJ::SITEROOT/search/' method='get'>";
    $ret .= "<input type='text' value='' size='12' name='q' id='SearchText' />";
    $ret .= "<select name='area'>
                <option value='default'><?_ml ysearch.findall _ml?></option>
                <option value='posts'><?_ml ysearch.findentries _ml?></option>
                <option value='comments'><?_ml ysearch.findcomments _ml?></option>
                <option value='journals' selected='1'><?_ml ysearch.findjournal _ml?></option>
                <option value='faq'><?_ml ysearch.faq _ml?></option>
            </select>";
    $ret .= "<input type='submit' value='" . BML::ml('horizon.search.submit') . "' /></form>";

    my $system = LJ::load_user('system') or die "No 'system' user in DB";
    my @keywords = split /\s+/, $system->prop('search_admin');
    $ret .= join ' ', map { "<a href='$LJ::SITEROOT/search/?q=" . LJ::eurl($_) . "&area=journals'>$_</a>" } @keywords;

    if (LJ::get_remote()) { # logged in
        $ret .= $class->ml('widget.searchjournals.loggedin.random', {url => "$LJ::SITEROOT/random.bml"});
    } else { # logged out
        $ret .= $class->ml('widget.searchjournals.loggedout.random');
        $ret .= "<form action='$LJ::SITEROOT/random.bml'>" . $class->html_submit($class->ml('widget.searchjournals.loggedout.random.button')) . "</form>";
    }

    return $ret;
}

1;
