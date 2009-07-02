var Aliases = {};

Aliases.init_catnav = function() {
    var navCats = DOM.getElementsByClassName(document, "vg_cat") || [];
    Array.prototype.forEach.call(navCats, function(cat){
        DOM.addEventListener(cat, "click", Aliases.navClicked.bindEventListener(cat));
    Aliases.link = Aliases.link || $('vg_cat_featured');
    DOM.addClassName(Aliases.link, "on");
    });
};

// Handle the event where the nav is clicked on
Aliases.navClicked = function(evt) {
    var id = this.id;
    if (Aliases.nav) Aliases.nav.style.display = "none";
    if (Aliases.link) DOM.removeClassName(Aliases.link, "on");

    Aliases.nav = $('show_'+id);
    Aliases.nav.style.display = "block";
    Aliases.link = this;
    DOM.addClassName(Aliases.link, "on");

    Event.stop(evt);
    return false;
};

LiveJournal.register_hook("page_load", function () {
    Aliases.init_catnav() });

function addAlias(target, ptitle, ljusername, oldalias) {
    if (! ptitle) return true;
    var addvgift = new LJWidgetIPPU_AddAlias({
        title: ptitle,
        width: 440,
        height: 130,
        authToken: Aliases.authToken
        }, {
            foruser: ljusername,
	    alias: oldalias,
        });

    return false;
}

