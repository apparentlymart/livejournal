var ESN_Inbox = new Object();

DOM.addEventListener(window, "load", function (evt) {
  ESN_Inbox.initTableSelection();
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
}

// Callback for when selected rows of the inbox change
ESN_Inbox.selectedRowsChanged = function (rows) {

}

