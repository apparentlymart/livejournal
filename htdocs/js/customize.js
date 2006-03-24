/*
  Helper functions for the s1/s2/customize/style/whatever frontend

  tabclick_init: On window load, change the links of the tabs to the current page
                 and add onclick event handlers that save the current tab

  tabclick_save: when navigating away from the current tab by clicking another tag,
                 save the contents of the current tab
                 

*/

function tabclick_save() {
    $("action:redir").value = this.id;
    $("display_form").submit();
}

function comment_options_toggle() {
    var inputs = $("comment_options").getElementsByTagName("input");
    var selects = $("comment_options").getElementsByTagName("select");
    var disabled = $("opt_showtalklinks").checked ? false : true;
    var color = $("opt_showtalklinks").checked ? "#000000" : "#999999";

    $("comment_options").style.color = color;
    for (var i = 0; i < inputs.length; i++) {
        inputs[i].disabled = disabled;
    }
    for (var i = 0; i < selects.length; i++) {
        selects[i].disabled = disabled;
    }

}

function s1_customcolors_toggle() {
    if ($("themetype:custom").checked) {
        $("s1_customcolors").style.display = "block";
    }
    if ($("themetype:system").checked) {
        $("s1_customcolors").style.display = "none";
    }
}

function customize_init() {
    var links = $('Tabs').getElementsByTagName('a');
    for (var i = 0; i < links.length; i++) {
        if (links[i].href != "") {
            links[i].href = "#";
            DOM.addEventListener(links[i], "click", tabclick_save.bindEventListener(links[i]));
        }
    }
    var s1_customcolors = $("s1_customcolors");
    if (s1_customcolors) {
        s1_customcolors_toggle();
        DOM.addEventListener($("themetype:custom"), "change", s1_customcolors_toggle);
        DOM.addEventListener($("themetype:system"), "change", s1_customcolors_toggle);
    }
    var opt_showtalklinks = $("opt_showtalklinks");
    if (opt_showtalklinks) {
        comment_options_toggle();
        DOM.addEventListener(opt_showtalklinks, "change", comment_options_toggle);
    }
}
DOM.addEventListener(window, "load", customize_init);
