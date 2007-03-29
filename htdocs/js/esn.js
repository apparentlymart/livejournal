var ESN = new Object();

LiveJournal.register_hook("page_load", function () {
  ESN.initCheckAllBtns();
  ESN.initEventCheckBtns();
  ESN.initTrackBtns();
});

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

// attach event handlers to all track buttons
ESN.initTrackBtns = function () {
    // don't do anything if no remote
    if (!Site || !Site.has_remote) return;

    // attach to all ljuser head icons
    var domObjects = document.getElementsByTagName("*");
    var trackBtns = DOM.filterElementsByClassName(domObjects, "TrackButton") || [];

    trackBtns.forEach(function (trackBtn) {
        if (!trackBtn || !trackBtn.getAttribute) return;

        if (!trackBtn.getAttribute("lj_subid") && !trackBtn.getAttribute("lj_journalid")) return;

        DOM.addEventListener(trackBtn, "click",
                             ESN.trackBtnClickHandler.bindEventListener(trackBtn));
    });
};

ESN.trackBtnClickHandler = function (evt) {
    var trackBtn = evt.target;
    if (! trackBtn || trackBtn.tagName.toLowerCase() != "img") return true;

    Event.stop(evt);

    var btnInfo = {};

    Array('arg1', 'arg2', 'etypeid', 'journalid', 'subid', 'auth_token').forEach(function (arg) {
        btnInfo[arg] = trackBtn.getAttribute("lj_" + arg);
    });

    // pop up little dialog to either track by inbox/email or go to more options
    var dlg = document.createElement("div");
    var defTrackBtn = document.createElement("input");
    defTrackBtn.type = "button";
    dlg.appendChild(defTrackBtn);
    defTrackBtn.value = Number(btnInfo["subid"]) ? "Stop tracking"
        : "Track with email notifications";

    var custTrackBtn = document.createElement("input");
    custTrackBtn.type = "button";
    dlg.appendChild(custTrackBtn);
    custTrackBtn.value = "More tracking options...";

    // global trackPopup so we can only have one
    if (ESN.trackPopup) {
        ESN.trackPopup.hide();
        ESN.trackPopup = null;
    }
    ESN.trackPopup = new LJ_IPPU.showNoteElement(dlg, trackBtn, 0);

    DOM.addEventListener(defTrackBtn, "click", function () {
        ESN.toggleSubscription(btnInfo, evt, trackBtn);
        if (ESN.trackPopup) ESN.trackPopup.hide();
    });

    DOM.addEventListener(custTrackBtn, "click", function () {
        document.location.href = trackBtn.parentNode.href;
        if (ESN.trackPopup) ESN.trackPopup.hide();
    });

    return false;
}

// (Un)subscribes to an event
ESN.toggleSubscription = function (subInfo, evt, btn) {
    var action = "";
    var params = {};

    if (Number(subInfo.subid)) {
        // subscription exists
        action = "delsub";
        params.subid = subInfo.subid;
    } else {
        // create a new subscription
        action = "addsub";

        Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
            if (Number(subInfo[param]))
                params[param] = parseInt(subInfo[param]);
        });
    }

    params.action     = action;
    params.auth_token = subInfo.auth_token;

    var reqInfo = {
        "method": "POST",
        "url":    LiveJournal.getAjaxUrl('esn_subs'),
        "data":   HTTPReq.formEncoded(params)
    };

    var gotInfoCallback = function (info) {
        if (! info) return LJ_IPPU.showNote("Error changing subscription", btn);

        if (info.error) return LJ_IPPU.showNote(info.error, btn);

        if (info.success) {
            if (info.msg)
                LJ_IPPU.showNote(info.msg, btn);

            if (info.subscribed) {
                btn.src = Site.imgprefix + "/btn_tracking.gif";

                DOM.setElementAttribute(btn, "lj_subid", info.subid);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    DOM.setElementAttribute(btn, "lj_" + param, 0);
                });

                DOM.setElementAttribute(btn, "title", 'Untrack This');
            } else {
                btn.src = Site.imgprefix + "/btn_track.gif";

                DOM.setElementAttribute(btn, "lj_subid", 0);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    DOM.setElementAttribute(btn, "lj_" + param, info[param]);
                });

                DOM.setElementAttribute(btn, "title", 'Track This');
            }

            DOM.setElementAttribute(btn, "lj_auth_token", info.auth_token);
        }
    };

    reqInfo.onData = gotInfoCallback;
    reqInfo.onError = function (err) { LJ_IPPU.showNote("Error: " + err) };

    HTTPReq.getJSON(reqInfo);
};
