LJWidgetIPPU = new Class(LJWidget, {
    init: function (opts, reqParams) {
        var title = opts.title;
        var widgetClass = opts.widgetClass;
        var nearEle = opts.nearElement;

        if (! reqParams) reqParams = {};
        this.reqParams = reqParams;

        // construct a container ippu for this widget
        var ippu = new LJ_IPPU(title);
        this.ippu = ippu;
        var c = document.createElement("div");
        c.id = "LJWidgetIPPU_" + Unique.id();
        ippu.setContentElement(c);

        ippu.show();

        c.innerHTML = "<big>Loading...</big>";

        // id, widgetClass, authToken (not needed)
        var widgetArgs = [c.id, widgetClass]
        LJWidgetIPPU.superClass.init.apply(this, widgetArgs);

        if (!widgetClass)
            return null;

        this.widgetClass = widgetClass;
        this.title = title;
        this.nearEle = nearEle;

        // start request for this widget now
        this.loadContent();
    },

    // override doAjaxRequest to add _widget_ippu = 1
    doAjaxRequest: function (params) {
      if (! params) params = {};
      params['_widget_ippu'] = 1;
      LJWidgetIPPU.superClass.doAjaxRequest.apply(this, [params]);
    },

    close: function () {
      this.ippu.hide();
    },

    loadContent: function () {
      var reqOpts = this.reqParams;
      this.updateContent(reqOpts);
    },

    method: "POST",

    // request finished
    onData: function (data) {

    },

    render: function (params) {

    }
});
