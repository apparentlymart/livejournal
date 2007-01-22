package LJ::Widget::RecentEntry;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;

    my %opts    = @_;
    my $show    = $opts{show} || 1;
    my $journal = $opts{journal};
    croak "no journal specified"
        unless $journal;
    my $journalu = LJ::load_user($journal);
    croak "invalid journal: $journal"
        unless LJ::isu($journalu);

    my $ret = "<em>RecentEntry:</em> ";

    my @items = LJ::get_recent_items({
        'userid'        => $journalu->id,
        'clusterid'     => $journalu->clusterid,
        'clustersource' => 'slave',
        'order'         => 'logtime',
        'itemshow'      => 1,
        'dateformat'    => 'S2',
    });
    my $item = $items[0];

    # silly, there's no journalid in the hashref
    # returned here, so we'll shove it in to
    # construct an LJ::Entry object.  : (
    $item->{journalid} = $journalu->id;

    my $entry = LJ::Entry->new_from_item_hash($items[0]);
    return "" unless $entry->event_text;

    # Display date as YYYY-MM-DD
    my $date = substr($entry->eventtime_mysql, 0, 10);

    $ret .= "<span class='date'>$date</span><br/>";
    $ret .= "<span class='subject'>" . $entry->subject_html . "</span><br /><br/>";
    $ret .= $entry->event_html;

    my $link = $entry->url;

    $ret .= "<div style='text-align: right'>( ";
    if (my $reply_ct = $entry->prop('replycount')) {
        $ret .= "<a href='$link'><b>" . ($reply_ct == 1 ? "1 comment" : "$reply_ct comments") . "</b></a>";
    } else {
        $ret .= "<a href='$link'><b>Link</b></a>";
    }
    unless ($entry->prop('opt_nocomments')) {
        $ret .= " | <a href='$link?mode=reply'><b>Leave a comment</b></a>";
    }
    $ret .= " )</div>";

    return $ret;
}

1;
