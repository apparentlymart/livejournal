package LJ::Widget::PopularInterests;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Stats;

sub need_res { qw( stc/widgets/popularinterests.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $get = $class->get_args;
    my $cart = $get->{'cart'} || $BML::COOKIE{cart};
    my $body;

    my $rows = LJ::Stats::get_popular_interests();
    @$rows = grep { !$LJ::INTERESTS_KW_FILTER{$_->[0]} } @$rows;
    my @rand = BML::randlist(@$rows);

    my $num_interests = 20;
    my $max = ((scalar @rand) < $num_interests) ? (scalar @rand) : $num_interests;

    my %interests;
    foreach my $int_array (@rand[0..$max-1]) {
        my ($int, $count) = @$int_array;
        $interests{$int} = {
                            int   => $int,
                            eint  => LJ::ehtml($int),
                            url   => "/interests.bml?int=" . LJ::eurl($int),
                            value => $count,
                            };
    }
    $body .= "<div class='right-mod'><div class='mod-tl'><div class='mod-tr'><div class='mod-br'><div class='mod-bl'>";
    $body .= "<div class='w-head'><h2><span class='w-head-in'>" . $class->ml('widget.popularinterests.title') . "</span></h2><i class='w-head-corner'></i></div>";
                            
    $body .= "<div class='w-body'>";
    $body .= "<p>" . LJ::tag_cloud(\%interests, {'font_size_range' => 16}) . "</p>";

    $body .= "<p class='viewall'>&raquo; <a href='$LJ::SITEROOT/interests.bml?view=popular'>" .
             $class->ml('widget.popularinterests.viewall') . "</a></p>";
    
    $body .= "</div></div></div></div></div></div>";

    return $body;
}

1;
