var ESN_Inbox = new Object();

ESN_Inbox.selected_qids = [];

DOM.addEventListener(window, "load", function (evt) {
  ESN_Inbox.initTableSelection();
  ESN_Inbox.initContentExpandButtons();
  ESN_Inbox.initInboxBtns();
});

// Set up table events
ESN_Inbox.initTableSelection = function () {
    var selectedRows = new SelectableTable;
    selectedRows.init({
        "table": $("inbox"),
            "selectedClass": "Selected",
            "multiple": true,
            "checkboxClass": "InboxItem_Check",
            "selectableClass": "InboxItem_Row"
            });

    if (!selectedRows) return;

    selectedRows.addWatcher(ESN_Inbox.selectedRowsChanged);

    // find selected checkboxes in rows, and select those rows
    var domElements = document.getElementsByTagName("input");
    var checkboxes = DOM.filterElementsByClassName(domElements, "InboxItem_Check") || [];

    Array.prototype.forEach.call(checkboxes, function (checkbox) {
        if (!checkbox.checked) return;

        var parentRow = DOM.getFirstAncestorByClassName(checkbox, "InboxItem_Row");
        if (parentRow)
            parentRow.rowClicked();
    });
};

// Callback for when selected rows of the inbox change
ESN_Inbox.selectedRowsChanged = function (rows) {
    // find the selected qids
    ESN_Inbox.selected_qids = [];
    rows.forEach(function (row) {
        ESN_Inbox.selected_qids.push(row.getAttribute("lj_qid"));
    });
};

// set up event handlers on expand buttons
ESN_Inbox.initContentExpandButtons = function () {
    var domElements = document.getElementsByTagName("*");
    var buttons = DOM.filterElementsByClassName(domElements, "InboxItem_Expand") || [];

    Array.prototype.forEach.call(buttons, function (button) {
        DOM.addEventListener(button, "click", function (evt) {
            // find content div
            var parent = DOM.getFirstAncestorByClassName(button, "InboxItem_Row");
            var children = parent.getElementsByTagName("div");
            var contentContainers = DOM.filterElementsByClassName(children, "InboxItem_Content");
            var contentContainer = contentContainers[0];

            if (!contentContainer) return true;

            if (contentContainer.style.display == "none") {
                contentContainer.style.display = "block";
                button.src = LJVAR.imgprefix + "/expand.gif";
            } else {
                contentContainer.style.display = "none";
                button.src = LJVAR.imgprefix + "/collapse.gif";
            }

            Event.stop(evt);
            return false;
        });
    });
};

// set up inbox buttons
ESN_Inbox.initInboxBtns = function () {
    DOM.addEventListener($("Inbox_MarkRead"), "click", ESN_Inbox.markRead);
    DOM.addEventListener($("Inbox_MarkUnread"), "click", ESN_Inbox.markUnread);
    DOM.addEventListener($("Inbox_Delete"), "click", ESN_Inbox.deleteItems);
    DOM.addEventListener($("Inbox_MarkAllRead"), "click", ESN_Inbox.markAllRead);
};

ESN_Inbox.markRead = function (evt) {
    Event.stop(evt);
    ESN_Inbox.updateItems('mark_read');
    return false;
};

ESN_Inbox.markUnread = function (evt) {
    Event.stop(evt);
    ESN_Inbox.updateItems('mark_unread');
    return false;
};

ESN_Inbox.deleteItems = function (evt) {
    Event.stop(evt);
    ESN_Inbox.updateItems('delete');
    return false;
};

ESN_Inbox.markAllRead = function (evt) {
    Event.stop(evt);
    ESN_Inbox.updateItems('mark_all_read');
    return false;
};

// do an ajax action on the currently selected items
ESN_Inbox.updateItems = function (action) {
    var postData = {
        "action": action,
        "qids": ESN_Inbox.selected_qids.join(",")
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "url": "/__rpc_esn_inbox",
        "onError": ESN_Inbox.reqError,
        "onData": ESN_Inbox.finishedUpdate
    };

    HTTPReq.getJSON(opts);
};

// got error doing ajax request
ESN_Inbox.reqError = function (error) {

};

// successfully completed request
ESN_Inbox.finishedUpdate = function (info) {
    if (!info || !info.success || !info.items) return;

    if (info.error) {
        return;
    }

    var unread_count = 0;

    info.items.forEach(function (item) {
        var qid     = item.qid;
        var read    = item.read;
        var deleted = item.deleted;
        if (!qid) return;

        if (!read) unread_count++;

        var rowElement = $("InboxItem_Row_" + qid);
        if (!rowElement) return;

        if (deleted) {
            rowElement.parentNode.removeChild(rowElement);
        } else {
            var titleElement = $("InboxItem_Title_" + qid);
            if (!titleElement) return;

            if (read) {
                DOM.removeClassName(titleElement, "InboxItem_Unread");
                DOM.addClassName(titleElement, "InboxItem_Read");
            } else {
                DOM.removeClassName(titleElement, "InboxItem_Read");
                DOM.addClassName(titleElement, "InboxItem_Unread");
            }
        }
    });

    $("Inbox_NewItems").innerHTML = "You have " + unread_count + " new " + (unread_count == 1 ? "message" : "messages") +
    (unread_count ? "!" : ".");
};
