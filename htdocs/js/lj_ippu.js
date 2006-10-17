LJ_IPPU = new Class ( IPPU, {
  init: function(title) {
    if (!title)
      title = "";

    LJ_IPPU.superClass.init.apply(this, []);

    this.uniqId = this.generateUniqId();
    this.cancelThisFunc = this.cancel.bind(this);

    this.setTitle(title);
    this.setTitlebar(true);
    this.setTitlebarClass("lj_ippu_titlebar");

    this.addClass("lj_ippu");

    this.setAutoCenterCallback(IPPU.center);
    this.setDimensions(400, "auto");
    this.setOverflow("hidden");

    this.setFixedPosition(true);
    this.setClickToClose(true);
    this.setAutoHideSelects(true);
  },

  setTitle: function (title) {
    var titlebarContent = "\
      <div style='float:right; padding-right: 8px'>" +
      "<img src='" + LJVAR.imgprefix + "/CloseButton.gif' width='15' height='15' id='" + this.uniqId + "_cancel' /></div>" + title;

    LJ_IPPU.superClass.setTitle.apply(this, [titlebarContent]);
  },

  generateUniqId: function() {
    var theDate = new Date();
    return "lj_ippu_" + theDate.getHours() + theDate.getMinutes() + theDate.getMilliseconds();
  },

  show: function() {
    LJ_IPPU.superClass.show.apply(this);
    var setupCallback = this.setup_lj_ippu.bind(this);
    window.setTimeout(setupCallback, 300);
  },

  setup_lj_ippu: function (evt) {
    var cancelCallback = this.cancelThisFunc;
    DOM.addEventListener($(this.uniqId + "_cancel"), "click", cancelCallback, true);
  },

  hide: function() {
    DOM.removeEventListener($(this.uniqId + "_cancel"), "click", this.cancelThisFunc, true);
    LJ_IPPU.superClass.hide.apply(this);
  }
} );

// Class method to show a popup to show a note to the user
// note = message to show
// underele = element to display the note underneath
LJ_IPPU.showNote = function (note, underele, timeout) {
    var noteElement = document.createElement("div");
    noteElement.innerHTML = note;

    return LJ_IPPU.showNoteElement(noteElement, underele, timeout);
};

LJ_IPPU.showNoteElement = function (noteEle, underele, timeout) {
    var notePopup = new IPPU();
    notePopup.init();

    var inner = document.createElement("div");
    DOM.addClassName(inner, "Inner");
    inner.appendChild(noteEle);
    notePopup.setContentElement(inner);

    notePopup.setTitlebar(false);
    notePopup.setFadeIn(true);
    notePopup.setFadeOut(true);
    notePopup.setFadeSpeed(4);
    notePopup.setDimensions("auto", "auto");
    notePopup.addClass("Note");

    var dim;
    if (underele) {
        // pop up the box right under the element
        dim = DOM.getAbsoluteDimensions(underele);
        if (!dim) return;
    }

    if (!dim) {
        notePopup.setModal(true);
        notePopup.setOverlayVisible(true);
        notePopup.setAutoCenter(true, true);
    } else {
        // default is to auto-center, don't want that
        notePopup.setAutoCenter(false, false);
        notePopup.setLocation(dim.absoluteLeft, dim.absoluteBottom + 4);
    }

    notePopup.setClickToClose(true);
    notePopup.show();
    notePopup.moveForward();

    if (! defined(timeout)) {
        timeout = 5000;
    }

    if (timeout) {
        window.setTimeout(function () {
            if (notePopup)
                notePopup.hide();
        }, timeout);
    }

    return notePopup;
};
