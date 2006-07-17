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

