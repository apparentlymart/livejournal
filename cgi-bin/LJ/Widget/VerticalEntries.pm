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

    my $page = $opts{page} > 0 ? $opts{page} : 1;
    my $num_full_entries_first_page = defined $opts{num_full_entries_first_page} ? $opts{num_full_entries_first_page} : 3;
    my $num_collapsed_entries_first_page = defined $opts{num_collapsed_entries_first_page} ? $opts{num_collapsed_entries_first_page} : 8;
    my $num_entries_older_pages = $opts{num_entries_older_pages} > 0 ? $opts{num_entries_older_pages} : 10;
    my $max_pages = $opts{max_pages} > 0 ? $opts{max_pages} : 10;

    my $num_entries_first_page = $num_full_entries_first_page + $num_collapsed_entries_first_page;
    my $num_entries_this_page = $page > 1 ? $num_entries_older_pages : $num_entries_first_page;
    my $start_index = $page > 1 ? (($page - 2) * $num_entries_this_page) + $num_entries_first_page : 0;

    my $r = Apache->request;
    my $return_url = "$LJ::SITEROOT" . $r->uri;
    my $args = $r->args;
    $return_url .= "?$args" if $args;

    my $ret;

    # get one more than we display so that we can tell if the next page will have entries or not
    my @entries_this_page = $vertical->entries( start => $start_index, limit => $num_entries_this_page + 1 );

    # pop off the last entry if we got more than we need, since we won't display it
    my $last_entry = pop @entries_this_page if @entries_this_page > $num_entries_this_page;

    my $title_displayed = 0;
    my $count = 0;
    my $collapsed_count = 0;
    foreach my $entry (@entries_this_page) {
        if ($page > 1 || $count < $num_full_entries_first_page) {
            $ret .= $class->print_entry( entry => $entry, vertical => $vertical, title_displayed => \$title_displayed, return_url => $return_url );
        } else {
            $ret .= "<table class='entry-collapsed' cellspacing='10'>" if $count == $num_full_entries_first_page;
            $ret .= "<tr>" if $collapsed_count % 2 == 0;
            $ret .= "<td>" . $class->print_collapsed_entry( entry => $entry, vertical => $vertical, title_displayed => \$title_displayed, return_url => $return_url ) . "</td>";
            $ret .= "</tr>" if $collapsed_count % 2 == 1;
            $ret .= "</table>" if $count == @entries_this_page - 1;
            $collapsed_count++;
        }
        $count++;
    }

    my $page_back = $page + 1;
    my $page_forward = $page - 1;
    my $show_page_back = defined $last_entry ? 1 : 0;
    my $show_page_forward = $page_forward > 0;

    $ret .= "<p class='skiplinks'>" if $show_page_back || $show_page_forward;
    if ($show_page_back) {
        $ret .= "<a href='" . $vertical->url . "?page=$page_back'>&lt; " . $class->ml('widget.verticalentries.skip.previous') . "</a>";
    }
    $ret .= " | " if $show_page_back && $show_page_forward;
    if ($show_page_forward) {
        my $url = $page_forward == 1 ? $vertical->url : $vertical->url . "?page=$page_forward";
        $ret .= "<a href='$url'>" . $class->ml('widget.verticalentries.skip.next') . " &gt;</a>";
    }
    $ret .= "</p>" if $show_page_back || $show_page_forward;

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
        $ret .= "<h2>" . $class->ml('widget.verticalentries.title2', { verticalname => $display_name }) . "</h2>";
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

    # remove from vertical button and categories button
    $ret .= $class->remove_btn( entry => $entry, vertical => $vertical );
    $ret .= $class->cats_btn( entry => $entry, return_url => $opts{return_url} );

    # subject
    $ret .= "<p class='subject'><a href='" . $entry->url . "'><strong>";
    $ret .= $entry->subject_text || "<em>" . $class->ml('widget.verticalentries.nosubject') . "</em>";
    $ret .= "</strong></a></p>";

    # entry text
    $ret .= "<p class='event'>" . $entry->event_html_summary(400) . " &hellip;</p>";

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

sub print_collapsed_entry {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $title_displayed_ref = $opts{title_displayed};

    my $display_name = $vertical->display_name;
    my $ret;

    # display the title in here so we don't show it if there's no entries to show
    unless ($$title_displayed_ref) {
        $ret .= "<h2>" . $class->ml('widget.verticalentries.title2', { verticalname => $display_name }) . "</h2>";
        $$title_displayed_ref = 1;
    }

    # remove from vertical button and categories button
    $ret .= $class->remove_btn( entry => $entry, vertical => $vertical );
    $ret .= $class->cats_btn( entry => $entry, return_url => $opts{return_url} );

    if ($entry->userpic) {
        $ret .= $entry->userpic->imgtag_nosize;
    } else {
        $ret .= LJ::run_hook('no_userpic_html');
    }
    $ret .= "<div class='pkg'>";

    $ret .= "<p class='collapsed-subject'><a href='" . $entry->url . "'><strong>";
    $ret .= $entry->subject_text || "<em>" . $class->ml('widget.verticalentries.nosubject') . "</em>";
    $ret .= "</strong></a></p>";
    $ret .= "<p class='collapsed-poster'>" . $entry->poster->ljuser_display;
    unless ($entry->posterid == $entry->journalid) {
        $ret .= " " . $class->ml('widget.verticalentries.injournal', { user => $entry->journal->ljuser_display });
    }
    $ret .= "</p>";

    # tags
    my @tags = $entry->tags;
    if (@tags) {
        my $tag_list = join(", ",
            map  { "<a href='" . LJ::eurl($entry->journal->journal_base . "/tag/$_") . "'>" . LJ::ehtml($_) . "</a>" }
            sort { lc $a cmp lc $b } @tags);
        $ret .= "<p class='collapsed-tags'>" . $class->ml('widget.verticalentries.tags') . " $tag_list</p>";
    }

    # post time and comments link
    my $secondsago = time() - $entry->logtime_unix;
    my $posttime = LJ::ago_text($secondsago);
    $ret .= "<p class='collapsed-posttime'>" . $class->ml('widget.verticalentries.posttime', { posttime => $posttime });
    $ret .= " | <a href='" . $entry->url . "'>";
    $ret .= $entry->reply_count ? $class->ml('widget.verticalentries.replycount', { count => $entry->reply_count }) : $class->ml('widget.verticalentries.nocomments');
    $ret .= "</a></p>";

    $ret .= "</div>";

    return $ret;
}

sub remove_btn {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    my $vertical = $opts{vertical};
    my $display_name = $vertical->display_name;

    my $ret;
    if ($vertical->remote_can_remove_entry($entry)) {
        my $confirm_text = $class->ml('widget.verticalentries.remove.confirm', { verticalname => $display_name });
        my $btn_alt = $class->ml('widget.verticalentries.remove.alt', { verticalname => $display_name });

        $ret .= LJ::Widget::VerticalContentControl->start_form(
            class => "remove-entry",
            onsubmit => "if (confirm('$confirm_text')) { return true; } else { return false; }"
        );
        $ret .= LJ::Widget::VerticalContentControl->html_hidden( remove => 1, entry_url => $entry->url, verticals => $vertical->vertid );
        $ret .= " <input type='image' src='$LJ::IMGPREFIX/btn_del.gif' alt='$btn_alt' title='$btn_alt' />";
        $ret .= LJ::Widget::VerticalContentControl->end_form;
    }

    return $ret;
}

sub cats_btn {
    my $class = shift;
    my %opts = @_;

    my $entry = $opts{entry};
    return "" unless LJ::run_hook("remote_can_get_categories_for_entry", $entry);

    my $btn_alt = $class->ml('widget.verticalentries.cats.alt');

    my $ret;
    $ret .= LJ::Widget::VerticalContentControl->start_form( class => "entry-cats", action => "$LJ::SITEROOT/admin/verticals/?action=cats" );
    $ret .= LJ::Widget::VerticalContentControl->html_hidden( cats => 1, entry_url => $entry->url, return_url => $opts{return_url} );
    $ret .= " <input type='image' src='$LJ::IMGPREFIX/btn_todo.gif' alt='$btn_alt' title='$btn_alt' />";
    $ret .= LJ::Widget::VerticalContentControl->end_form;

    return $ret;
}

1;
