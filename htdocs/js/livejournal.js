// This file contains general-purpose LJ code
// $id$

var LiveJournal = new Object;

// The hook mappings
LiveJournal.hooks = {};

LiveJournal.register_hook = function (hook, func) {
    LiveJournal.hooks[hook] = func;
};

// args: hook, params to pass to hook
LiveJournal.run_hook = function () {
    var a = arguments;

    var hookfunc = LiveJournal.hooks[a[0]];
    if (!hookfunc || !hookfunc.apply) return;

    var hookargs = [];

    for (var i = 1; i < a.length; i++) {
        hookargs.push(a[i]);
    }

    return hookfunc.apply(null, hookargs);
};

// deal with placeholders
DOM.addEventListener(window, "load", function (e) {
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
});
