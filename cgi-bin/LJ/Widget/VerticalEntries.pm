package LJ::Widget::VerticalEntries;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical );

sub need_res { qw( stc/widgets/verticalentries.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $skip = $opts{skip} > 0 ? $opts{skip} : 0;
    my $entries_per_page = $opts{entries_per_page} > 0 ? $opts{entries_per_page} : 10;
    my $max_pages = $opts{max_pages} > 0 ? $opts{max_pages} : 10;

    my $ret;

    # get one more than we display so that we can tell if the next page will have entries or not
    my @entries_this_page = $vertical->entries( start => $skip, limit => $entries_per_page + 1 );

    # pop off the last entry if we got more than we need, since we won't display it
    my $last_entry = pop @entries_this_page if @entries_this_page > $entries_per_page;

    my $title_displayed = 0;
    foreach my $entry (@entries_this_page) {
        $ret .= $class->print_entry( entry => $entry, vertical => $vertical, title_displayed => \$title_displayed );
    }

    my $skip_back = $skip + $entries_per_page;
    my $skip_forward = $skip - $entries_per_page;
    my $show_skip_back = defined $last_entry ? 1 : 0;
    my $show_skip_forward = $skip_forward >= 0;

    $ret .= "<p class='skiplinks'>" if $show_skip_back || $show_skip_forward;
    if ($show_skip_back) {
        $ret .= "<a href='" . $vertical->url . "&skip=$skip_back'>&lt; " . $class->ml('widget.verticalentries.skip.previous', { num => $entries_per_page }) . "</a>";
    }
    $ret .= " | " if $show_skip_back && $show_skip_forward;
    if ($show_skip_forward) {
        my $url = $skip_forward == 0 ? $vertical->url : $vertical->url . "&skip=$skip_forward";
        $ret .= "<a href='$url'>" . $class->ml('widget.verticalentries.skip.next', { num => $entries_per_page }) . " &gt;</a>";
    }
    $ret .= "</p>" if $show_skip_back || $show_skip_forward;

    return $ret;
}

sub print_entry {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $title_displayed_ref = $opts{title_displayed};

    my $display_name = $vertical->display_name;
    my $ret;

    # display the title in here so we don't show it if there's no entries to show
    unless ($$title_displayed_ref) {
        $ret .= "<h2>" . $class->ml('widget.verticalentries.title', { verticalname => $display_name }) . "</h2>";
        $$title_displayed_ref = 1;
    }

    $ret .= "<table class='entry'><tr>";

    $ret .= "<td class='userpic'>";
    if ($entry->userpic) {
        $ret .= $entry->userpic->imgtag_lite;
    } else {
        $ret .= LJ::run_hook('no_userpic_html');
    }
    $ret .= "<p class='poster'>" . $entry->poster->ljuser_display;
    unless ($entry->posterid == $entry->journalid) {
        $ret .= "<br />" . $class->ml('widget.verticalentries.injournal', { user => $entry->journal->ljuser_display });
    }
    $ret .= "</p></td>";

    $ret .= "<td class='content'>";

    # subject
    $ret .= "<p class='subject'><a href='" . $entry->url . "'><strong>";
    $ret .= $entry->subject_text || "<em>" . $class->ml('widget.verticalentries.nosubject') . "</em>";
    $ret .= "</strong></a></p>";

    # remove from vertical button
    if ($vertical->remote_can_remove_entry($entry)) {
        my $confirm_text = $class->ml('widget.verticalentries.remove.confirm', { verticalname => $display_name });
        my $btn_alt = $class->ml('widget.verticalentries.remove.alt', { verticalname => $display_name });

        $ret .= LJ::Widget::VerticalContentControl->start_form(
            onsubmit => "if (confirm('$confirm_text')) { return true; } else { return false; }"
        );
        $ret .= LJ::Widget::VerticalContentControl->html_hidden( remove => 1, entry_url => $entry->url, verticals => $vertical->vertid );
        $ret .= " <input type='image' src='$LJ::IMGPREFIX/btn_del.gif' alt='$btn_alt' title='$btn_alt' />";
        $ret .= LJ::Widget::VerticalContentControl->end_form;
    }

    # entry text
    $ret .= "<p class='event'>" . LJ::html_trim($entry->event_text, 0, 400) . " &hellip;</p>";

    # tags
    my @tags = $entry->tags;
    if (@tags) {
        my $tag_list = join(", ",
            map  { "<a href='" . LJ::eurl($entry->journal->journal_base . "/tag/$_") . "'>" . LJ::ehtml($_) . "</a>" }
            sort { lc $a cmp lc $b } @tags);
        $ret .= "<p class='tags'>" . $class->ml('widget.verticalentries.tags') . " $tag_list</p>";
    }

    # post time and comments link
    my $secondsago = time() - $entry->logtime_unix;
    my $posttime = LJ::ago_text($secondsago);
    $ret .= "<p class='posttime'>" . $class->ml('widget.verticalentries.posttime', { posttime => $posttime });
    $ret .= " | <a href='" . $entry->url . "'>";
    $ret .= $entry->reply_count ? $class->ml('widget.verticalentries.replycount', { count => $entry->reply_count }) : $class->ml('widget.verticalentries.nocomments');
    $ret .= "</a></p>";

    $ret .= "</td>";
    $ret .= "</tr></table>";

    $ret .= "<hr />";

    return $ret;
}

1;
