/*global Hourglass, DOM */

var Customize = {};

Customize.init = function () {
    Customize.cat = '';
    Customize.layoutid = 0;
    Customize.designer = '';
    Customize.search = '';
    Customize.filter_available = 0;
    Customize.page = 1;
    Customize.show = 12;
    Customize.hourglass = null;

    var pageGetArgs = LiveJournal.parseGetArgs(document.location.href);

    if (pageGetArgs['cat']) {
        Customize.cat = pageGetArgs['cat'];
    }

    if (pageGetArgs['layoutid']) {
        Customize.layoutid = pageGetArgs['layoutid'];
    }

    if (pageGetArgs['designer']) {
        Customize.designer = pageGetArgs['designer'];
    }

    if (pageGetArgs['search']) {
        Customize.search = pageGetArgs['search'];
    }

    if (pageGetArgs['filter_available']) {
        Customize.filter_available = pageGetArgs['filter_available'];
    }

    if (pageGetArgs['page']) {
        Customize.page = pageGetArgs['page'];
    }

    if (pageGetArgs['show']) {
        Customize.show = pageGetArgs['show'];
    }
};

Customize.resetFilters = function () {
    Customize.cat = '';
    Customize.layoutid = 0;
    Customize.designer = '';
    Customize.search = '';
    Customize.page = 1;
};

Customize.cursorHourglass = function (evt) {
    var pos = DOM.getAbsoluteCursorPosition(evt);

    if (!pos) {
        return;
    }

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.setPosition(pos.x, pos.y);
        Customize.hourglass.show();
    }
};

Customize.elementHourglass = function (element) {
    if (!element) {
        return;
    }

    if (!Customize.hourglass) {
        Customize.hourglass = new Hourglass();
        Customize.hourglass.setContainer(element);
        Customize.hourglass.show();
    }
};

Customize.hideHourglass = function () {
    if (Customize.hourglass) {
        Customize.hourglass.hide();
        Customize.hourglass.remove();
        Customize.hourglass = null;
    }
};

LiveJournal.register_hook('page_load', Customize.init);
