var ESN_Inbox = new Object();

DOM.addEventListener(window, "load", function (evt) {
  ESN_Inbox.initTableSelection();
  ESN_Inbox.initContentExpandButtons();
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
};

// Callback for when selected rows of the inbox change
ESN_Inbox.selectedRowsChanged = function (rows) {

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

