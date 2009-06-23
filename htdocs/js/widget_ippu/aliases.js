LJWidgetIPPU_AddAlias = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::AddAlias";
    this.width = opts.width; // Use for resizing later
    this.height = opts.height; // Use for resizing later
    LJWidgetIPPU_AddAlias.superClass.init.apply(this, arguments);
  },

  addvgifttocart: function (evt, form) {
    var alias = form["Widget[IPPU_AddAlias]_alias"].value + "";
    var foruser = form["Widget[IPPU_AddAlias]_foruser"].value + "";

    this.doPost({
        alias:          alias,
        foruser:            foruser
    });

    Event.stop(evt);
  },

  onData: function (data) {
    var success;
    if (data.res && data.res.success) success = data.res.success;
    if (success) {
      LJ_IPPU.showNote("Virtual gift added to your cart.");
      this.ippu.hide();
    }
  },

  onError: function (msg) {
    LJ_IPPU.showErrorNote("Error: " + msg);
  },

  onRefresh: function () {
    var self = this;
//    var cancelBtn = $('addvgift_cancel');
//    if (cancelBtn) DOM.addEventListener(cancelBtn, 'click', self.cancel.bindEventListener(this));

    var form = $("addalias_form");
    DOM.addEventListener(form, "submit", function(evt) { self.addvgifttocart(evt, form) });

//    $('Widget[IPPU_AddAlias]_whom').value = this.whom;
//    AutoCompleteFriends($('Widget[IPPU_AddAlias]_whom'));
  },

  cancel: function (e) {
    this.close();
  }
});
