package LJ::Widget::PopularInterests;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Stats;

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $get = $class->get_args;
    my $cart = $get->{'cart'} || $BML::COOKIE{cart};
    my $body;

    my $rows = LJ::Stats::get_popular_interests();
    my @rand = BML::randlist(@$rows);

    my $num_interests = 30;
    my $max = ((scalar @rand) < $num_interests) ? (scalar @rand) : $num_interests;

    my %interests;
    foreach my $int_array (@rand[1..$max]) {
        my ($int, $count) = @$int_array;
        $interests{$int} = {
                            int   => $int,
                            eint  => LJ::ehtml($int),
                            url   => "/interests.bml?int=" . LJ::eurl($int),
                            value => $count,
                            };
    }

    $body .= "<p>" . LJ::tag_cloud(\%interests) . "</p>";

    $body .= "<p>&raquo; <a href='$LJ::SITEROOT/interests.bml?view=popular'>" .
             BML::ml('widget.interests.viewall') . "</a></p>";

    return $body;
}

1;
