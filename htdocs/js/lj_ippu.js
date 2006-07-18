LJ_IPPU = new Class ( IPPU, {
  init: function(title) {
    if (!title)
      title = "";

    LJ_IPPU.superClass.init.apply(this, []);

    this.uniqId = this.generateUniqId();
    this.cancelThisFunc = this.cancel.bind(this);

    var titlebarContent = "\
      <div style='width:100%; text-align:left; padding: 4px; border: 0px solid yellow;'><div style='float:right; padding-right: 8px'>" +
      "<img src='" + LJVAR.imgprefix + "/CloseButton.gif' width='15' height='15' id='" + this.uniqId + "_cancel' /></div>" + title + "</div>";

    log(LJVAR.imgprefix + "/img/CloseButton.gif");

    this.setTitlebar(true);
    this.setTitle(titlebarContent);
    this.setTitlebarClass("lj_ippu_titlebar");

    this.addClass("lj_ippu");

    this.setAutoCenterCallback(IPPU.center);
    this.setDimensions(400, "auto");
    this.setOverflow("hidden");

    this.setFixedPosition(true);
    this.setClickToClose(true);
    this.setAutoHideSelects(true);
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
