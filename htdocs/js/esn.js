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
                DOM.setElementAttribute(btn, "lj_subid", info.subid);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    DOM.setElementAttribute(btn, "lj_" + param, 0);
                });

                DOM.setElementAttribute(btn, "title", 'Untrack This');

                // update subthread tracking icons
                var dtalkid = btn.getAttribute("lj_dtalkid");
                if (dtalkid)
                    ESN.updateThreadIcons(dtalkid, "on");
                else // not thread tracking button
                    btn.src = Site.imgprefix + "/btn_tracking.gif";
            } else {
                DOM.setElementAttribute(btn, "lj_subid", 0);

                Array("journalid", "arg1", "arg2", "etypeid").forEach(function (param) {
                    DOM.setElementAttribute(btn, "lj_" + param, info[param]);
                });

                DOM.setElementAttribute(btn, "title", 'Track This');

                // update subthread tracking icons
                var dtalkid = btn.getAttribute("lj_dtalkid");
                if (dtalkid) {
                    // set state to "off" if no parents tracking this,
                    // otherwise set state to "parent"
                    var state = "off";
                    var parentBtn;
                    var parent_dtalkid = dtalkid;
                    while (parentBtn = ESN.getThreadParentBtn(parent_dtalkid)) {
                        parent_dtalkid = parentBtn.getAttribute("lj_dtalkid");
                        if (! parent_dtalkid) {
                            log("could not find parent_dtalkid");
                            break;
                        }

                        if (! Number(parentBtn.getAttribute("lj_subid")))
                            continue;
                        state = "parent";
                        break;
                    }

                    ESN.updateThreadIcons(dtalkid, state);
                } else {
                    // not thread tracking button
                    btn.src = Site.imgprefix + "/btn_track.gif";
                }
            }

            DOM.setElementAttribute(btn, "lj_auth_token", info.auth_token);
        }
    };

    reqInfo.onData = gotInfoCallback;
    reqInfo.onError = function (err) { LJ_IPPU.showNote("Error: " + err) };

    HTTPReq.getJSON(reqInfo);
};

// given a dtalkid, find the track button for its parent comment (if any)
ESN.getThreadParentBtn = function (dtalkid) {
    var cmtInfo = LJ_cmtinfo[dtalkid + ""];
    if (! cmtInfo) {
        log("no comment info");
        return null;
    }

    var parent_dtalkid = cmtInfo.parent;
    if (! parent_dtalkid)
        return null;

    return $("lj_track_btn_" + parent_dtalkid);
};

// update all the tracking icons under a parent comment
ESN.updateThreadIcons = function (dtalkid, tracking) {
    var btn = $("lj_track_btn_" + dtalkid);
    if (! btn) {
        log("no button");
        return;
    }

    var cmtInfo = LJ_cmtinfo[dtalkid + ""];
    if (! cmtInfo) {
        log("no comment info");
        return;
    }

    if (Number(btn.getAttribute("lj_subid")) && tracking != "on") {
        // subscription already exists on this button, don't mess with it
        return;
    }

    if (cmtInfo.rc && cmtInfo.rc.length) {
        // update children
        cmtInfo.rc.forEach(function (child_dtalkid) {
            window.setTimeout(function () {
                var state;
                switch (tracking) {
                case "on":
                    state = "parent";
                    break;
                case "off":
                    state = "off";
                    break;
                case "parent":
                    state = "parent";
                    break;
                default:
                    alert("Unknown tracking state " + tracking);
                    break;
                }
                ESN.updateThreadIcons(child_dtalkid, state);
            }, 300);
        });
    }

    // update icon
    var uri;
    switch (tracking) {
        case "on":
            uri = "/btn_tracking.gif";
            break;
        case "off":
            uri = "/btn_track.gif";
            break;
        case "parent":
            uri = "/btn_tracking_thread.gif";
            break;
        default:
            alert("Unknown tracking state " + tracking);
            break;
    }

    btn.src = Site.imgprefix + uri;
};
