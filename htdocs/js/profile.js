var Profile = new Object();

Profile.init = function () {
    // add event listeners to all of the headers
    var headers = DOM.getElementsByClassName(document, "expandcollapse");
    headers.forEach(function (header) {
        DOM.addEventListener(header, "click", function (evt) { Profile.expandCollapse(header.id) });
    });
}

Profile.expandCollapse = function (headerid) {
    var self = this;
    var bodyid = headerid.replace(/header/, 'body');
    var arrowid = headerid.replace(/header/, 'arrow');

    // figure out whether to expand or collapse
    var expand = !DOM.hasClassName($(headerid), 'on');

    if (expand) {
        // expand
        DOM.addClassName($(headerid), 'on');
        if ($(arrowid)) { $(arrowid).src = Site.imgprefix + "/profile_icons/arrow-down.gif"; }
        if ($(bodyid)) { $(bodyid).style.display = "block"; }
    } else {
        // collapse
        DOM.removeClassName($(headerid), 'on');
        if ($(arrowid)) { $(arrowid).src = Site.imgprefix + "/profile_icons/arrow-right.gif"; }
        if ($(bodyid)) { $(bodyid).style.display = "none"; }
    }
}

LiveJournal.register_hook("page_load", Profile.init);
