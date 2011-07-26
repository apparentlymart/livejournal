package LJ::Widget::InboxFolder;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::TimeUtil;
use constant ITEMS_PER_PAGE => 15;

# DO NOT COPY
# This widget is not a good example of how to use JS and AJAX.
# This widget's render_body outputs HTML similar to the HTML
# output originally by the Notifications Inbox page. This was
# done so that the existing JS, CSS and Endpoints could be used.

sub need_res {
    return qw(
            js/core.js
            js/dom.js
            js/view.js
            js/controller.js
            js/datasource.js
            js/checkallbutton.js
            js/selectable_table.js
            js/httpreq.js
            js/hourglass.js
            js/esn_inbox.js
            stc/esn.css
            stc/lj_base.css
            );
}

# args
#   folder: the view or subset of notification items to display
#   reply_btn: should we show a reply button or link
#   expand: display a specified in expanded view
#   inbox: NotificationInbox object
#   items: list of notification items
#   selected: message to expanded view (page is ignored)
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $name = $opts{folder};
    my $show_reply_btn = $opts{reply_btn} || 0;
    my $expand = $opts{expand} || 0;
    my $inbox = $opts{inbox};
    my $nitems = $opts{items};
    my $page = $opts{page} || 1;
    my $view = $opts{view} || "all";
    my $remote = LJ::get_remote();
    my $selected = $opts{selected} || 0; # this is msgid

    my $unread_count = 1; #TODO get real number
    my $disabled = $unread_count ? '' : 'disabled';

    # print form
    my $msgs_body .= qq {
        <form action="$LJ::SITEROOT/inbox/" method="POST" id="${name}Form">
        };

    $msgs_body .= LJ::html_hidden({
                    name  => "view",
                    value => "$view",
                    id    => "inbox_view",
                  });

    # pagination
    my $page_limit = ITEMS_PER_PAGE;
    $page = 1 if $page < 1;
    my $last_page = POSIX::ceil((scalar @$nitems) / $page_limit);
    $last_page ||= 1;
    $page = $last_page if $page > $last_page;

    @$nitems = sort { $b->when_unixtime <=> $a->when_unixtime } @$nitems;

    # find page for selected item 
    my $selected_page = __get_page_by_selected_item($selected, $nitems);
    $page = $selected_page ? $selected_page : $page;

    my $prev_disabled = ($page <= 1) ? 'disabled' : '';
    my $next_disabled = ($page >= $last_page) ? 'disabled' : '';

    my $actionsrow = sub {
        my $sfx = shift; # suffix

        # check all checkbox
        my $checkall = LJ::html_check({
            id      => "${name}_CheckAll_$sfx",
            class   => "InboxItem_Check",
        });
        
        if (LJ::is_enabled('spam_inbox') && $view eq 'spam') {
            return qq {
                 <tr class="header" id="ActionRow$sfx">
                        <td class="checkbox">$checkall</td>
                        <td class="actions" colspan="2">
                            <span class="Pages">
                                Page $page of $last_page
                                <input type="button" id="Page_Prev_$sfx" value="$BML::ML{'.btn.prev'}" $prev_disabled />
                                <input type="button" id="Page_Next_$sfx" value="$BML::ML{'.btn.next'}" $next_disabled />
                            </span>
                            <input type="submit" name="delete_$sfx" value="$BML::ML{'.btn.delete'}" id="${name}_Delete_$sfx" />
                            <input type="submit" name="unspam_$sfx" value="$BML::ML{'.btn.unspam'}" id="${name}_UnSpam_$sfx" />
                        </td>
                </tr>
            };
        } else {
            return qq {
                 <tr class="header" id="ActionRow$sfx">
                        <td class="checkbox">$checkall</td>
                        <td class="actions" colspan="2">
                            <span class="Pages">
                                Page $page of $last_page
                                <input type="button" id="Page_Prev_$sfx" value="$BML::ML{'.btn.prev'}" $prev_disabled />
                                <input type="button" id="Page_Next_$sfx" value="$BML::ML{'.btn.next'}" $next_disabled />
                            </span>
                            <input type="submit" name="markRead_$sfx" value="$BML::ML{'.btn.read'}" $disabled id="${name}_MarkRead_$sfx" />
                            <input type="submit" name="markUnread_$sfx" value="$BML::ML{'.btn.unread'}" id="${name}_MarkUnread_$sfx" />
                            <input type="submit" name="delete_$sfx" value="$BML::ML{'.btn.delete'}" id="${name}_Delete_$sfx" />
                            <input type="submit" name="spam_$sfx" value="$BML::ML{'.btn.spam'}" id="${name}_Spam_$sfx" />
                        </td>
                </tr>
            };
        }
    };
    
    # create table of messages
    my $messagetable = qq {
     <div id="${name}_Table" class="NotificationTable">
        <table id="${name}" class="inbox" cellspacing="0" border="0" cellpadding="0">
        };
    $messagetable .= $actionsrow->(1);
    $messagetable .= "<tbody id='${name}_Body'>";

    unless (@$nitems) {
        $messagetable .= qq {
            <tr><td class="NoItems" colspan="3" id="NoMessageTD">No Messages</td></tr>
            };
    }

    # print out messages
    my $rownum = 0;
    my $starting_index = ($page - 1) * $page_limit;
    for (my $i = $starting_index; $i < $starting_index + $page_limit; $i++) {
        my $inbox_item = $nitems->[$i];
        last unless $inbox_item;

        my $qid  = $inbox_item->qid;

        my $read_class = $inbox_item->read ? "InboxItem_Read" : "InboxItem_Unread";

        my $title  = $inbox_item->title(mode => $opts{mode});

        my $checkbox_name = "${name}_Check-$qid";
        my $checkbox = LJ::html_check({
            id    => $checkbox_name,
            class => "InboxItem_Check",
            name  => $checkbox_name,
        });

        # HTML for displaying bookmark flag
        my $bookmark = $inbox->is_bookmark($qid)
            ? "on"
            : "off";
        $bookmark = "<a href='$LJ::SITEROOT/inbox/?page=$page&bookmark_$bookmark=$qid'><img src='$LJ::IMGPREFIX/flag_$bookmark.gif' width='16' height='18' class='InboxItem_Bookmark' border='0' /></a>";

        my $when = LJ::TimeUtil->ago_text(time() - $inbox_item->when_unixtime);
        my $contents = $inbox_item->as_html || '';

        my $row_class = ($rownum++ % 2 == 0) ? "InboxItem_Meta" : "InboxItem_Meta alt";

        my $expandbtn = '';
        my $content_div = '';

        if ($contents) {
            BML::ebml(\$contents);

            # Was item selected by id?
            my $expand_selected = __was_item_selected($selected, $inbox_item);

            # Does item need to be expanded?
            my $expanded = ( $expand && $expand == $qid ) || $expand_selected;
            $expanded ||= $remote->prop('esn_inbox_default_expand');
            if ( $inbox_item->read && !$expand_selected ) {
                $expanded = 0 ;
            }

            my $img = $expanded ? "expand.gif" : "collapse.gif";

            $expandbtn = qq {
                <a href="$LJ::SITEROOT/inbox/?page=$page&expand=$qid"><img src="$LJ::IMGPREFIX/$img" class="InboxItem_Expand" border="0" onclick="return false" /></a>
                };

            my $display = $expanded ? "block" : "none";

            $content_div = qq {
                <div class="InboxItem_Content" style="display: $display;">$contents</div>
                };
        }

        $messagetable .= qq {
            <tr class="InboxItem_Row $row_class" lj_qid="$qid" id="${name}_Row_$qid">
                <td class="checkbox">$checkbox</td>
                <td class="item">
                    <div class="InboxItem_Controls">$bookmark $expandbtn</div>
                    <span class="$read_class" id="${name}_Title_$qid">$title</span>
                    $content_div
                    </td>
                    <td class="time">$when</td>
                </tr>
        };
    }

    $messagetable .= $actionsrow->(2);

    $messagetable .= '</tbody></table></div>';

    $messagetable .= qq {
      <div style="text-align: center; margin-top: 20px;">
        <input type="submit" name="markAllRead" value="Mark All Read" $disabled id="${name}_MarkAllRead" style="margin-right: 5em; width: 12em;" />
        <input type="submit" name="deleteAll" value="Delete All" $disabled id="${name}_DeleteAll" style="width: 12em;" />
     </div>
    };

    $msgs_body .= $messagetable;

    $msgs_body .= LJ::html_hidden({
        name  => "page",
        id    => "pageNum",
        value => $page,
    });

    $msgs_body .= qq {
        </form>
        };

    # JS confirm dialog that appears when a user tries to delete a bookmarked item
    $msgs_body .= "<script>ESN_Inbox.confirmDelete = '" . $class->ml('widget.inboxfolder.confirm.delete') . "';</script>";

    return $msgs_body;
}


sub __was_item_selected {
    my ($selected, $inbox_item) = @_;
    return 0 unless $selected;

    my $event = $inbox_item->event;

    if ($event) {
        my $msgid = $event->arg1;
        return $msgid == $selected;
    }
}

sub __get_page_by_selected_item {
    my ($selected, $nitems) = @_;
    my $page = 0;
    return $page unless $selected;

    my $index = 0;
    while (1) {
        my $inbox_item = $nitems->[$index];
        last unless $inbox_item;
        my $event = $inbox_item->event;

        if ($event) {
            my $msgid = $event->arg1;
            
            if ($msgid == $selected) {
                $page = int($index / ITEMS_PER_PAGE) + 1;
            }
        }
        $index++;
    }
    return $page;
}

1;
