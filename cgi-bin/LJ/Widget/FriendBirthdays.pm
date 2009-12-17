package LJ::Widget::FriendBirthdays;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use List::Util qw/shuffle/;

sub need_res {
    return qw( stc/widgets/friendbirthdays.css );
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
   
    $ret .= "<h2><span>" . $class->ml('widget.friendbirthdays.title') . "</span></h2>";
    $ret .= "<a href='$LJ::SITEROOT/birthdays.bml' class='more-link'>" . $class->ml('widget.friendbirthdays.viewall') . "</a></p>";
    $ret .= "<div class='indent_sm'><table>";

    foreach my $bday (@bdays) {
        my $u = LJ::load_user($bday->[2]);
        my $month = $bday->[0];
        my $day = $bday->[1];
        next unless $u && $month && $day;

        # remove leading zero on day
        $day =~ s/^0//;

        $ret .= "<tr>";
        $ret .= "<td>" . $u->ljuser_display . "</td>";
        $ret .= "<td>" . $class->ml('widget.friendbirthdays.userbirthday', {'month' => LJ::Lang::month_short($month), 'day' => $day}) . "</td>";
        $ret .= "<td><a href='$LJ::SITEROOT/shop/view.bml?item=paidaccount&gift=1&for=" . $u->user . "' class='gift-link'>";
        $ret .= $class->ml('widget.friendbirthdays.gift') . "</a></td>";
        $ret .= "</tr>";
    }

    $ret .= "</table></div>";

    unless ($LJ::DISABLED{'vgift_list'} || $opts{'no_vgifts'}) {
        my $to = $u->user;
        $to =~ s/([^a-zA-Z0-9-_])//g; # Remove bad chars from lj-user name

        unless (defined $BML::COOKIE{show_sponsored_vgifts}) {
            $BML::COOKIE{show_sponsored_vgifts} = ($u->get_cap('paid')) ? 0 : 1;
        }
        my $get_sponsor_vgift = defined $opts{get}->{sponsor_vgift} ? $opts{get}->{sponsor_vgift} : $BML::COOKIE{show_sponsored_vgifts};
        $BML::COOKIE{show_sponsored_vgifts} = $get_sponsor_vgift if $get_sponsor_vgift =~ /^[01]$/;

        my $show_to_sup = LJ::SUP->is_remote_sup ? 1 : 0;
 
        my %friend_birtdays_vgifts = LJ::run_hook('get_friend_birthdays_vgifts', $u);
        %friend_birtdays_vgifts = %LJ::FRIEND_BIRTHDAYS_VGIFTS unless %friend_birtdays_vgifts;

        $ret .= "<h3>". $class->ml('widget.friendbirthdays.sendgift') ."</h3>";
        
        $ret .= "<ul class='giftlist'>";
        my ($spons_cnt, $vgift_cnt) = (0, 0);
        my @need_vgifts = ();
        
        my $array_shuffle = sub {
            my $array = shift;
            my $i = @$array;
            while (--$i) {
                my $j = int rand($i+1);
                @$array[$i,$j] = @$array[$j,$i];
            }
        };

        my $is_show_href = 0;
        foreach my $vg_key (sort { $friend_birtdays_vgifts{$b}->{sponsored} <=> $friend_birtdays_vgifts{$a}->{sponsored} } keys %friend_birtdays_vgifts) {
            next unless $vg_key;
            next if $friend_birtdays_vgifts{$vg_key}->{show_to_sup} ne $show_to_sup;
            $is_show_href++ if $friend_birtdays_vgifts{$vg_key}->{sponsored};
            next if $friend_birtdays_vgifts{$vg_key}->{sponsored} && !$get_sponsor_vgift;
            next if ++$spons_cnt > 2 and $friend_birtdays_vgifts{$vg_key}->{sponsored};
            last if ++$vgift_cnt > 3;
            push @need_vgifts, $vg_key;
        }

        @need_vgifts = shuffle (@need_vgifts);
        foreach my $vg_key (@need_vgifts) {
            my $vg_link = $friend_birtdays_vgifts{$vg_key}->{url};
            my $vg = LJ::Pay::ShopVGift->new(id => $vg_key);
            my $vg_html = $vg->display_html_code(
                remove_url => 1,
                hover => LJ::ehtml($vg->name( remove_url => 1 )),
            );
            my $vg_name = $vg->name( remove_url => 1 );
            my $vg_price = ($vg->price+0)  ? '<b>' . $vg->price . '$</b>' : '<b style="color:#FF0000;">' . $class->ml('widget.friendbirthdays.freegift') . '</b>' ;
            $ret .= "<li><div class='gift-holder'><span class='liner'></span><a href=\"$vg_link\">$vg_html</a></div><span>$vg_name<br />$vg_price</span></li>";
        }
        my $show_hide_href = '';
        $show_hide_href .= "<a href='$LJ::SITEROOT/?sponsor_vgift=1'>" . $class->ml('widget.friendbirthdays.show_sponsored_vgifts') . "</a><br/>" unless $get_sponsor_vgift;
        $show_hide_href .= "<a href='$LJ::SITEROOT/?sponsor_vgift=0'>" . $class->ml('widget.friendbirthdays.hide_sponsored_vgifts') . "</a><br/>" if $get_sponsor_vgift;

        $ret .=	"</ul>";
        $ret .= $show_hide_href if @need_vgifts && $is_show_href && $u->get_cap('paid');

        $ret .= "<a href='$LJ::SITEROOT/shop/vgift.bml'>" . $class->ml('widget.friendbirthdays.moregifts') . " &rarr;</a>";
    }

    $ret .= "<p class='indent_sm'>&raquo; <a href='$LJ::SITEROOT/birthdays.bml'>" .
            $class->ml('widget.friendbirthdays.friends_link') .
            "</a></p>" if $opts{friends_link};
    $ret .= "<p class='indent_sm'>&raquo; <a href='$LJ::SITEROOT/paidaccounts/friends.bml'>" .
            $class->ml('widget.friendbirthdays.paidtime_link') .
            "</a></p>" if $opts{paidtime_link};

    $ret .= '</div></div></div></div></div>';
    
        
    return $ret;
}

1;
