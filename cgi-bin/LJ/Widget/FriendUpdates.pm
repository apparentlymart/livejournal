package LJ::Widget::FriendUpdates;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/widget-layout.css stc/widgets/friendupdates.css );
}

# args
#   user: optional $u whose friend updates we should get (remote is default)
#   limit: optional max number of updates to show; default is 5
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my $cache_inbox_key  = "friend_updates:" . $u->userid;
    my $cache_inbox_data = LJ::MemCache::get($cache_inbox_key);
    if ($cache_inbox_data) {
        return $cache_inbox_data;
    }

    my $inbox = $u->notification_inbox;
    my @notifications = ();
    if ($inbox) {
        @notifications = $inbox->friend_items;
        @notifications = sort { $b->when_unixtime <=> $a->when_unixtime } @notifications;
        @notifications = @notifications[0..$limit-1] if @notifications > $limit;
    }

    my $ret;

    $ret .= '<div class="right-mod"><div class="mod-tl"><div class="mod-tr"><div class="mod-br"><div class="mod-bl">';
    $ret .= '<div class="w-head">';
    $ret .= "<h2><span class='w-head-in'>" . $class->ml('widget.friendupdates.title') . "</span></h2>";
    $ret .= "<a href='$LJ::SITEROOT/inbox/' class='more-link'>" . $class->ml('widget.friendupdates.viewall') . "</a>";
    $ret .= '<i class="w-head-corner"></i></div>';
    $ret .= '<div class="w-body">';  
    unless (@notifications) {
        $ret .= $class->ml('widget.friendupdates.noupdates');
        $ret .= "<p class='detail'>" . $class->ml('widget.friendupdates.noupdates.setup', {'aopts' => "href='$LJ::SITEROOT/manage/subscriptions/'"}) . "</p>";
        #return $ret;
    }

    $ret .= "<ul class='nostyle'>";
    foreach my $item (@notifications) {
        $ret .= "<li>" . $item->title . "</li>";
    }
    $ret .= "</ul>";
    #$ret .= "<div class='statlink'>". $class->ml('widget.friendupdates.statistics', {'aopts' => "href='$LJ::SITEROOT/manage/subscriptions/'"}) ."</div>";

    $ret .= '</div></div></div></div></div></div>';

    LJ::MemCache::set($cache_inbox_key, $ret, 84600);

    return $ret;
}

1;
