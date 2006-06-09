ContextualPopup = new Object;

ContextualPopup.popupDelay = 1000;

ContextualPopup.cachedResults = {};
ContextualPopup.currentRequests = {};
ContextualPopup.mouseTimer = null;
ContextualPopup.elements = {};

ContextualPopup.setup = function (e) {
    // attach to all ljuser head icons
      var domObjects = document.getElementsByTagName("*");
      var ljusers = DOM.filterElementsByClassName(domObjects, "ljuser") || [];

      var headIcons = [];
      ljusers.forEach(function (ljuser) {
          var nodes = ljuser.getElementsByTagName("img");
          for (var i=0; i < nodes.length; i++) {
              var node = nodes.item(i);

              node.username = DOM.extractElementText(ljuser);

              headIcons.push(node);
              DOM.addClassName(node, "ContextualPopup");
          }
      });

      var ctxPopupId = 1;
      headIcons.forEach(function (headIcon) {
          ContextualPopup.elements[ctxPopupId + ""] = headIcon;
          headIcon.ctxPopupId = ctxPopupId++;
          DOM.addEventListener(document.body, "mousemove", ContextualPopup.mouseOver.bindEventListener());
      });
}

ContextualPopup.isCtxPopElement = function (ele) {
    return (ele && DOM.getAncestorsByClassName(ele, "ContextualPopup", true).length);
}

ContextualPopup.mouseOver = function (e) {
    var target = e.target;

    // did the mouse move out?
    if (!target || !ContextualPopup.isCtxPopElement(target)) {
        ContextualPopup.mouseOut(e);
        return;
    }

    var ctxPopupId = target.ctxPopupId + "";
    var username = target.username;

    if (!ctxPopupId || !username)
    return;

    var cached = ContextualPopup.cachedResults[ctxPopupId];

    // if we don't have cached data background request it
    if (!cached) {
        ContextualPopup.getInfo(username, ctxPopupId);
    }

    // start timer if it's not running
    if (! ContextualPopup.mouseTimer && ! ContextualPopup.ippu) {
        ContextualPopup.mouseTimer = window.setTimeout(function () {
            ContextualPopup.showPopup(ctxPopupId);
        }, ContextualPopup.popupDelay);
    }
}

ContextualPopup.mouseOut = function (e) {
    if (ContextualPopup.mouseTimer) {
        window.clearTimeout(ContextualPopup.mouseTimer);
    }

    ContextualPopup.mouseTimer = null;

    ContextualPopup.hidePopup();
}

ContextualPopup.showPopup = function (ctxPopupId) {
    if (ContextualPopup.mouseTimer) {
        window.clearTimeout(ContextualPopup.mouseTimer);
    }
    ContextualPopup.mouseTimer = null;

    if (ContextualPopup.ippu) {
        return;
    }

    ContextualPopup.constructIPPU(ctxPopupId);

    var ele = ContextualPopup.elements[ctxPopupId + ""];
    if (! ele) {
        return;
    }

    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.show();
        ContextualPopup.ippu.centerOnWidget(ele);
    }
}

ContextualPopup.constructIPPU = function (ctxPopupId) {
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }

    var ippu = new LJ_IPPU();
    ippu.init();
    ippu.setTitlebar(false);
    ippu.setDimensions("auto", "auto");
    ippu.addClass("ContextualPopup");
    ContextualPopup.ippu = ippu;

    ContextualPopup.renderPopup(ctxPopupId);
}

ContextualPopup.renderPopup = function (ctxPopupId) {
    var ippu = ContextualPopup.ippu;

    if (!ippu || !ctxPopupId)
    return;

    var data = ContextualPopup.cachedResults[ctxPopupId];
    if (data) {
        var content = document.createElement("div");
        DOM.addClassName(content, "Content");

        // userpic
        if (data.url_userpic) {
            var userpicContainer = document.createElement("div");
            var userpic = document.createElement("img");
            userpic.src = data.url_userpic;

            userpicContainer.appendChild(userpic);
            DOM.addClassName(userpicContainer, "Userpic");

            content.appendChild(userpicContainer);
        }

        // user name
        var displayName = document.createElement("div");
        displayName.innerHTML = data.display;
        DOM.addClassName(displayName, "Name");

        // profile
        var profile = document.createElement("div");
        var profileLink = document.createElement("a");
        profileLink.href = data.url_profile;
        profileLink.innerHTML = "Profile";
        profile.appendChild(profileLink);
        DOM.addClassName(profile, "Profile");

        // journal
        var journal = document.createElement("div");
        var journalLink = document.createElement("a");
        journalLink.href = data.url_journal;
        journalLink.innerHTML = "Journal";
        journal.appendChild(journalLink);
        DOM.addClassName(journal, "Journal");

        // friend?
        var relation = document.createElement("div");
        relation.innerHTML = data.username + " is " + (
                                                       data.is_friend ? "a friend" : "not a friend"
                                                       );

        if (! data.is_friend) {
            // add friend link
            var addFriend = document.createElement("div");
            var addFriendLink = document.createElement("a");
            addFriendLink.href = data.url_addfriend;
            addFriendLink.innerHTML = "Add as friend";
            addFriend.appendChild(addFriendLink);
            DOM.addClassName(addFriend, "AddFriend");
            relation.appendChild(addFriend);
        }

        DOM.addClassName(relation, "Relation");

        // set popup content
        content.appendChild(displayName);
        content.appendChild(profile);
        content.appendChild(journal);
        content.appendChild(relation);
        ippu.setContentElement(content);
    } else {
        ippu.setContent("loading...");
    }

}

ContextualPopup.hidePopup = function (ctxPopupId) {
    // destroy popup for now
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }
}

// do ajax request of user info
ContextualPopup.getInfo = function (username, ctxPopupId) {
    if (!username && !ctxPopupId)
        return;

    ctxPopupId += "";

    if (ContextualPopup.currentRequests[ctxPopupId]) {
        return;
    }

    ContextualPopup.currentRequests[ctxPopupId] = 1;

    var params = HTTPReq.formEncoded ({
        "user": username,
            "reqdata": ctxPopupId,
            "mode": "getinfo"
    });

    HTTPReq.getJSON({
        "url": "/tools/endpoints/ctxpopup.bml",
            "method" : "GET",
            "data": params,
            "onData": ContextualPopup.gotInfo,
            "onError": ContextualPopup.gotError
            });
}

// FIXME: remove after debugging
ContextualPopup.gotError = function (err) {
    log("error: " + err);
}

ContextualPopup.gotInfo = function (data) {
    var ctxPopupId = data.reqdata;
    if (!ctxPopupId)
    return;

    ContextualPopup.currentRequests[ctxPopupId] = null;

    ContextualPopup.cachedResults[ctxPopupId] = data;
    ContextualPopup.renderPopup(ctxPopupId);
}

// when page loads, set up contextual popups
DOM.addEventListener(window, "load", ContextualPopup.setup.bindEventListener());
