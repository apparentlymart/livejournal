package LJ::Widget::CategoryCommunities;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Browse );
use LJ::TimeUtil;

sub need_res { qw( stc/browse.css stc/widgets/categorycommunities.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $cat = $opts{cat};
    my $title = $opts{title};
    die "Invalid browse object passed to widget." unless $cat;

    my $ret;

    $$title .= $cat->title_html;
    $ret .= '<table class="communities" cellpadding="0" cellspacing="0" width="100%"><tbody>
    <tr style="" class="head"><td style="" colspan="2">Community</td><td style="">Updated</td></tr>';

    my @comms = $cat->communities;
    my %top_comms;
    %top_comms = map { $_ => 1 } $cat->top_communities if $cat->top_communities;
    my $feat;
    my $cret;
    foreach my $comm (@comms) {
        next unless LJ::isu($comm);
        my $secondsold = $comm->timeupdate ? time() - $comm->timeupdate : undef;
        if ($top_comms{$comm->userid}) {
            $feat .= "<tr class='featured'><td class='userpic'>";
            $feat .= $comm->userpic ?
                    $comm->userpic->imgtag_percentagesize(0.5) :
                    LJ::run_hook('no_userpic_html', percentage => 0.5 );
            $feat .= "</td>";
            $feat .= "<td class='content'><p class='collapsed-poster'>" .
                    $comm->ljuser_display({ bold => 0, head_size => 11 }) .
                    "</p><p class='collapsed-subject'>" .
                    "<a href='" . $comm->journal_base . "'><strong>" .
                    $comm->prop('journaltitle') . "</strong></a><br />" .
                    $comm->prop('journalsubtitle') . "</p>" .
                    "</td><td class='posted' valign='top'>" .
                    LJ::TimeUtil->ago_text($secondsold) .
                    "</td></tr>\n";

        } else {
            $cret .= "<tr class='regular'><td class='content' colspan='2'>" .
                     "<p class='collapsed-poster'>" .
                     $comm->ljuser_display({ bold => 0, head_size => 11 }) .
                     "</p><p class='collapsed-subject'>" .
                     "<a href='" . $comm->journal_base . "'><strong>" .
                     $comm->prop('journaltitle') . "</strong></a><br />" .
                     $comm->prop('journalsubtitle') . "</p>" .
                     "</td><td class='posted' valign='top'>" .
                     LJ::TimeUtil->ago_text($secondsold) .
                     "</td></tr>\n";
        }
    }
    $cret = $feat . $cret;
    $ret .= $cret ? $cret :
           "<tr><td colspan='100%' class='content'><i>No communities in this category yet</i></td></tr>";

    $ret .= "</table>\n";

    return $ret;
}

1;
