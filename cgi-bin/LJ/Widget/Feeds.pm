package LJ::Widget::Feeds;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $get = $class->get_args;
    my $cart = $get->{'cart'} || $BML::COOKIE{cart};
    my $body;
    $body .= "<div><h2 class='solid-neutral'>Feeds</h2>";

    # get user IDs of most popular feeds
    my $popsyn = LJ::Syn::get_popular_feed_ids();
    my @rand = BML::randlist(@$popsyn);

    my $feednum = 10;
    my $max = ((scalar @rand) < $feednum) ? (scalar @rand) : $feednum;
    $body .= "<div style='margin-left: 5px'>";
    $body .= "<table>";
    my $odd = 1;
    foreach my $userid (@rand[1..$max]) {
        my $u = LJ::load_userid($userid);
        $body .= "<tr>" if ($odd);
        $body .= "<td>" . LJ::ljuser($u) . "</td>";
        $body .= "<td style='padding-right: 10px'>" . $u->name_html . "</td>";
        $body .= "</tr>" unless ($odd);
        $odd = $odd ? 0 : 1;
    }

    $body .= "</table>";
    $body .= "<p style='padding-left: 4px'>&raquo; <a href='$LJ::SITEROOT/syn/list.bml'>" .
             BML::ml('widget.feeds.viewall') . "</a></p>";

    # Form to add or find feeds
    if ($remote) {
        $body .= "<div style='padding-left: 4px'><form method='post' action='$LJ::SITEROOT/syn/'>";
        $body .= LJ::html_hidden('userid', $remote->userid);
        $body .= "<b>" . BML::ml('widget.feeds.find') . "</b><br />";
        my $prompt = BML::ml('widget.feeds.enterRSS');
        $body .= LJ::html_text({ name    => 'synurl', size => '40',
                                 maxlength => '255',
                                 value   => "$prompt",
                                 onfocus => "if(this.value=='$prompt')this.value='';",
                                 onblur  => "if(this.value=='')this.value='$prompt';"});
        $body .= " " . LJ::html_submit("action:addcustom", BML::ml('btn.add'));
        $body .= "</form></div>";
    }

    $body .= "</div>";
    $body .= "</div>";

    return $body;
}

1;
