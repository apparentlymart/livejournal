var CategoryBrowse = {};

// Add Listeners to category controls shrink & grow([-|+])
CategoryBrowse.init_subcats = function() {
    var subCats = DOM.getElementsByClassName(document, "catsummary-outer") || [];
    Array.prototype.forEach.call(subCats, function(cat){
        var controls = DOM.getElementsByClassName(cat, "control") || [];
        Array.prototype.forEach.call(controls, function(control){
            DOM.addEventListener(control, "click", CategoryBrowse.controlClick.bindEventListener(control));
        });
    });
};

// Handle a click on a control
CategoryBrowse.controlClick = function(evt) {
    var control = this;
    var cat = DOM.getFirstAncestorByClassName(control, 'catsummary-outer', false);
    if (DOM.hasClassName(control, "shrink")) {
        CategoryBrowse.subcatShrink(control, cat);
    } else {
        CategoryBrowse.subcatGrow(control, cat);
    }

    Event.stop(evt);
    return false;
};

LiveJournal.register_hook("page_load", function () {
    CategoryBrowse.init_subcats() });

CategoryBrowse.subcatShrink = function(control, cat) {
    var subCats = DOM.getElementsByClassName(cat, 'catsummary-subcats') || [];
    Array.prototype.forEach.call(subCats, function(subCat){
        subCat.style.display = "none";
    });

    var topCats = DOM.getElementsByClassName(cat, 'catsummary-topcats') || [];
    Array.prototype.forEach.call(topCats, function(subCat){
        subCat.style.display = "block";
    });
    DOM.removeClassName(control, "shrink");
    DOM.addClassName(control, "grow");
    control.innerHTML = "[:) ";
};
CategoryBrowse.subcatGrow = function(control, cat) {
    var subCats = DOM.getElementsByClassName(cat, 'catsummary-subcats') || [];
    Array.prototype.forEach.call(subCats, function(subCat){
        subCat.style.display = "block";
    });

    var topCats = DOM.getElementsByClassName(cat, 'catsummary-topcats') || [];
    Array.prototype.forEach.call(topCats, function(subCat){
        subCat.style.display = "none";
    });
    DOM.removeClassName(control, "grow");
    DOM.addClassName(control, "shrink");
    control.innerHTML = "[:P";
};
