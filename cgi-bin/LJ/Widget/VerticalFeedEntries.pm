package LJ::Widget::VerticalFeedEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/verticalfeedentries.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $u = LJ::load_user($LJ::VERTICAL_TREE{$vertical->name}->{feed});
    return "" unless $u && $u->is_syndicated;

    # - make sure to get enough entries in case the feed has a lot of entries posted at the same time
    # --- reason: $u->recent_entries gets data sorted by time, so if a lot of entries have the same time
    #     you may not get back the ones you want (i.e. the ones that appear at the top of the recent
    #     entries or friends page)
    # - sort them by jitemid (newest first) and print $num_to_print of them

    my $num_to_print = $opts{num} || 4;
    my $min_to_get = $opts{min_to_get} || 30;
    my $num_to_get = $num_to_print > $min_to_get/2 ? $num_to_print*2 : $min_to_get;
    my @entries = $u->recent_entries( count => $num_to_get );
    @entries = sort { $b->jitemid <=> $a->jitemid } @entries;

    my $ret;
    my $num_printed = 0;
    foreach my $entry (@entries) {
        last if $num_printed == $num_to_print;

        next unless $entry;
        my $link = $entry->syn_link;
        next unless $link;

        $ret .= "<a href='$link'>";
        $ret .= $entry->subject_text || "<em>" . $class->ml('widget.verticalfeedentries.nosubject') . "</em>";
        $ret .= "</a><br />";

        $num_printed++;
    }

    return $ret;
}

1;
