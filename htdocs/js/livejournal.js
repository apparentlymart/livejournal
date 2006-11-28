// This file contains general-purpose LJ code
// $Id$

var LiveJournal = new Object;

// The hook mappings
LiveJournal.hooks = {};

LiveJournal.register_hook = function (hook, func) {
    if (! LiveJournal.hooks[hook])
        LiveJournal.hooks[hook] = [];

    LiveJournal.hooks[hook].push(func);
};

// args: hook, params to pass to hook
LiveJournal.run_hook = function () {
    var a = arguments;

    var hookfuncs = LiveJournal.hooks[a[0]];
    if (!hookfuncs || !hookfuncs.length) return;

    var hookargs = [];

    for (var i = 1; i < a.length; i++) {
        hookargs.push(a[i]);
    }

    var rv = null;

    hookfuncs.forEach(function (hookfunc) {
        rv = hookfunc.apply(null, hookargs);
    });

    return rv;
};

LiveJournal.pageLoaded = false;

LiveJournal.initPage = function () {
    // only run once
    if (LiveJournal.pageLoaded)
        return;
    LiveJournal.pageLoaded = 1;

    // set up various handlers for every page
    LiveJournal.initPlaceholders();
    LiveJournal.initLabels();
    LiveJournal.initInboxUpdate();
    LiveJournal.initAds();
    
    // run other hooks
    LiveJournal.run_hook("page_load");
};

// Set up two different ways to test if the page is loaded yet.
// The proper way is using DOMContentLoaded, but only Mozilla supports it.
// So, the page_load hook will be fired when the DOM is loaded or after 1.5 seconds, whichever comes first
{
    // Others
    window.setTimeout(LiveJournal.initPage, 1500);

    // Mozilla
    DOM.addEventListener(window, "DOMContentLoaded", LiveJournal.initPage);
}

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
    // Don't run if not logged in or this is disabled
    if (! LJVAR || ! LJVAR.has_remote || ! LJVAR.inbox_update_poll) return;

    // Don't run if no inbox count
    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

    // Update every five minutes
    window.setInterval(LiveJournal.updateInbox, 1000 * 60 * 5);
};

// Do AJAX request to find the number of unread items in the inbox
LiveJournal.updateInbox = function () {
    var postData = {
        "action": "get_unread_items"
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "onData": LiveJournal.gotInboxUpdate
    };

    opts.url = LJVAR.currentJournal ? "/" + LJVAR.currentJournal + "/__rpc_esn_inbox" : "/__rpc_esn_inbox";

    HTTPReq.getJSON(opts);
};

// We received the number of unread inbox items from the server
LiveJournal.gotInboxUpdate = function (resp) {
    if (! resp || resp.error) return;

    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

    unread.innerHTML = resp.unread_count ? "  (" + resp.unread_count + ")" : "";
};

// Search for placeholders and initialize them
LiveJournal.initPlaceholders = function () {
    var domObjects = document.getElementsByTagName("*");
    var placeholders = DOM.filterElementsByClassName(domObjects, "LJ_Placeholder") || [];

    Array.prototype.forEach.call(placeholders, function (placeholder) {
        var parent = DOM.getFirstAncestorByClassName(placeholder, "LJ_Placeholder_Container", false);

        var containers = DOM.filterElementsByClassName(parent.getElementsByTagName("div"), "LJ_Container");
        var container = containers[0];
        if (!container) return;

        var placeholder_html = unescape(container.getAttribute("lj_placeholder_html"));

        DOM.addEventListener(placeholder, "click", function (e) {
            Event.stop(e);

            // have to wrap placeholder_html in another block, IE is weird
            container.innerHTML = "<span>" + placeholder_html + "</span>";

            DOM.makeInvisible(placeholder);
        });

        return false;
    });
};

// set up labels for Safari
LiveJournal.initLabels = function () {
    // safari doesn't know what <label> tags are, lets fix them
    if (navigator.userAgent.indexOf('Safari') == -1) return;

    // get all labels
    var labels = document.getElementsByTagName("label");

    for (var i = 0; i < labels.length; i++) {
        DOM.addEventListener(labels[i], "click", LiveJournal.labelClickHandler);
    }
};

LiveJournal.labelClickHandler = function (evt) {
    Event.prep(evt);

    var label = DOM.getAncestorsByTagName(evt.target, "label", true)[0];
    if (! label) return;

    var targetId = label.getAttribute("for");
    if (! targetId) return;

    var target = $(targetId);
    if (! target) return;

    target.click();

    return false;
};

// change drsc to src for ads
LiveJournal.initAds = function () {
    var ads = DOM.getElementsByAttribute('','dsrc');
    if (ads.length > 0) {
       for (i=0;i<ads.length;i++) {
           var url = ads[i].getAttribute('dsrc');
           ads[i].setAttribute('src',url);
       }
    }
};

// insert ads
insertAd = function (params) {
    var e = document.getElementById( params.id );
    if( !e )
        return;
    if( params.html ) {
        var e2 = document.createElement( "div" );
        e2.innerHTML = params.html;
        e.innerHTML = ""; // clear old content
        e.appendChild( e2 );
    }
    if( params.js )
        return eval( "(" + params.js + ")" );
}
