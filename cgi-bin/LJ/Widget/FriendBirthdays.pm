package LJ::Widget::FriendBirthdays;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use List::Util qw/shuffle/;

sub need_res {
    return qw( stc/widgets/widget-layout.css stc/widgets/friendbirthdays.css );
}

# args
#   user: optional $u whose friend birthdays we should get (remote is default)
#   limit: optional max number of birthdays to show; default is 5
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my @bdays = $u->get_friends_birthdays( months_ahead => 1 );
    @bdays = @bdays[0..$limit-1]
        if @bdays > $limit;

    return "" unless @bdays;

    my $ret;

    $ret .= '<div class="right-mod"><div class="mod-tl"><div class="mod-tr"><div class="mod-br"><div class="mod-bl">';
    $ret .= "<div class='w-head'>";
    $ret .= "<h2><span class='w-head-in'>" . $class->ml('widget.friendbirthdays.title') . "</span></h2> ";
    $ret .= "<a href='$LJ::SITEROOT/birthdays.bml' class='more-link'>" . $class->ml('widget.friendbirthdays.viewall') . "</a>";
    $ret .= "<i class='w-head-corner'></i></div>";

    $ret .= "<div class='w-body'>";
    $ret .= "<table>";

    foreach my $bday (@bdays) {
        my $u = LJ::load_user($bday->[2]);
        my $month = $bday->[0];
        my $day = $bday->[1];
        next unless $u && $month && $day;

        my $wishes = LJ::WishList->load_current($u);
        my $wish_url = $u->journal_base . "/wishlist";

        # remove leading zero on day
        $day =~ s/^0//;

        $ret .= "<tr>";
        $ret .= "<td>" . $u->ljuser_display . "</td>";
        $ret .= "<td>" . $class->ml('widget.friendbirthdays.userbirthday', {'month' => LJ::Lang::month_short($month), 'day' => $day}) . "</td>";
        $ret .= "<td><a href='$LJ::SITEROOT/shop/view.bml?item=paidaccount&gift=1&for=" . $u->user . "' title='" .  $class->ml('widget.friendbirthdays.gift') . "' class='gift-link'><span>";
        $ret .= $class->ml('widget.friendbirthdays.gift') . "</span></a></td>";
        $ret .= "<td>" . (scalar @$wishes ? "<a href='$wish_url' class='wish-link' title='" . $class->ml('widget.friendbirthdays.wishlist') . "'><span>" . $class->ml('widget.friendbirthdays.wishlist') . "</span></a>" : "&nbsp;") . "</td>";
        $ret .= "</tr>";
    }

    $ret .= "</table>";

    $ret .= "<ul class='b-list-options'>"  if  $opts{friends_link} or $opts{paidtime_link};
    $ret .= "<li>&raquo; <a href='$LJ::SITEROOT/birthdays.bml'>" .
            $class->ml('widget.friendbirthdays.friends_link') .
            "</a></li>" if $opts{friends_link};
    $ret .= "<li>&raquo; <a href='$LJ::SITEROOT/paidaccounts/friends.bml'>" .
            $class->ml('widget.friendbirthdays.paidtime_link') .
            "</a></li>" if $opts{paidtime_link};
    $ret .= "</ul>"  if  $opts{friends_link} or $opts{paidtime_link};

    $ret .= '</div></div></div></div></div></div>';
    
        
    return $ret;
}

1;
