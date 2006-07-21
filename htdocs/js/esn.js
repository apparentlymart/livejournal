var ESN = new Object();

DOM.addEventListener(window, "load", function (evt) {
  ESN.initCheckAllBtns();
  ESN.initEventCheckBtns();
  ESN.initTrackBtns();
});

// attach event handlers to all track buttons
ESN.initTrackBtns = function () {
    // don't do anything if no remote
    if (!LJVAR || !LJVAR.has_remote) return;

    // attach to all ljuser head icons
    var domObjects = document.getElementsByTagName("*");
    var trackBtns = DOM.filterElementsByClassName(domObjects, "TrackButton") || [];

    trackBtns.forEach(function (trackBtn) {
        if (!trackBtn || !trackBtn.getAttribute) return;

        if (!trackBtn.getAttribute("lj:subid") && !trackBtn.getAttribute("lj:journalid")) return;

        DOM.addEventListener(trackBtn, "click", function (evt) {
            Event.stop(evt);

            var btnInfo = {};

            Array('arg1', 'arg2', 'etypeid', 'journalid', 'subid', 'auth_token').forEach(function (arg) {
                btnInfo[arg] = trackBtn.getAttribute("lj:" + arg);
            });

            ESN.toggleSubscription(btnInfo, evt, trackBtn);
            return false;
        });
    });
};

// (Un)subscribes to an event
ESN.toggleSubscription = function (subInfo, evt, btn) {
    var action = "";
    var params = {};

    if (subInfo.subid) {
        // subscription exists
        action = "delsub";
        params.subid = subInfo.subid;
    } else {
        // create a new subscription
        action = "addsub";

        Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
            if (subInfo[param])
                params[param] = parseInt(subInfo[param]);
        });
    }

    params.action     = action;
    params.auth_token = subInfo.auth_token;

    var reqInfo = {
        "method": "POST",
        "url":    "/__rpc_esn",
        "data":   HTTPReq.formEncoded(params)
    };

    var gotInfoCallback = function (info) {
        if (! info) return LJ_IPPU.showNote("Error saving subscription", btn);

        if (info.error) return LJ_IPPU.showNote(info.error, btn);

        if (info.success) {
            if (info.msg)
                LJ_IPPU.showNote(info.msg, btn);

            if (info.subscribed) {
                btn.src = LJVAR.imgprefix + "/btn_tracking.gif";

                btn.setAttribute("lj:subid", info.subid);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    btn.setAttribute("lj:" + param, null);
                });
            } else {
                btn.src = LJVAR.imgprefix + "/btn_track.gif";

                btn.setAttribute("lj:subid", null);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    btn.setAttribute("lj:" + param, info[param]);
                });
            }

            btn.setAttribute("lj:auth_token", info.auth_token);
        }
    };

    reqInfo.onData = gotInfoCallback;
    reqInfo.onError = function (err) { LJ_IPPU.showNote("Error: " + err) };

    HTTPReq.getJSON(reqInfo);
};

// When page loads, set up "check all" checkboxes
ESN.initCheckAllBtns = function () {
  var ntids  = $("ntypeids");
  var catids = $("catids");

  if (!ntids || !catids)
    return;

  ntidList  = ntids.value;
  catidList = catids.value;

  if (!ntidList || !catidList)
    return;

  ntids  = ntidList.split(",");
  catids = catidList.split(",");

  catids.forEach( function (catid) {
    ntids.forEach( function (ntypeid) {
      var className = "SubscribeCheckbox-" + catid + "-" + ntypeid;

      var cab = new CheckallButton();
      cab.init({
        "class": className,
          "button": $("CheckAll-" + catid + "-" + ntypeid),
          "parent": $("CategoryRow-" + catid)
          });
    });
  });
}

// set up auto show/hiding of notification methods
ESN.initEventCheckBtns = function () {
  var viewObjects = document.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "SubscriptionInboxCheck") || [];

  boxes.forEach( function (box) {
    DOM.addEventListener(box, "click", ESN.eventChecked.bindEventListener());
  });
}

ESN.eventChecked = function (evt) {
  var target = evt.target;
  if (!target)
    return;

  var parentRow = DOM.getFirstAncestorByTagName(target, "tr", false);

  var viewObjects = parentRow.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "NotificationOptions") || [];

  boxes.forEach( function (box) {
    box.style.visibility = target.checked ? "visible" : "hidden";
  });
}
