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

DOM.addEventListener(window, "load", function (e) {
    LiveJournal.initPlaceholders();
    LiveJournal.initLabels();
});

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
