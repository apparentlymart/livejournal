ContextualPopup = new Object;

ContextualPopup.popupDelay = 1000;

ContextualPopup.cachedResults = {};
ContextualPopup.currentRequests = {};
ContextualPopup.mouseInTimer = null;
ContextualPopup.mouseOutTimer = null;
ContextualPopup.currentId = null;
ContextualPopup.elements = {};

ContextualPopup.setup = function (e) {
    // attach to all ljuser head icons
    var domObjects = document.getElementsByTagName("*");
    var ljusers = DOM.filterElementsByClassName(domObjects, "ljuser") || [];

    var userElements = [];
    ljusers.forEach(function (ljuser) {
        var nodes = ljuser.getElementsByTagName("img");
        for (var i=0; i < nodes.length; i++) {
            var node = nodes.item(i);

            node.username = DOM.extractElementText(ljuser);

            userElements.push(node);
            DOM.addClassName(node, "ContextualPopup");
        }
    });

    // attach to all userpics
    var images = DOM.filterElementsByTagName(domObjects, "img") || [];
    images.forEach(function (image) {
        // if the image url matches a regex for userpic urls then attach to it
        if (image.src.match(/userpic\..+\/\d+\/\d+/)) {
            image.up_url = image.src;
            DOM.addClassName(image, "ContextualPopup");
            userElements.push(image);
        }
    });

    var ctxPopupId = 1;
    userElements.forEach(function (userElement) {
        ContextualPopup.elements[ctxPopupId + ""] = userElement;
        userElement.ctxPopupId = ctxPopupId++;
        DOM.addEventListener(document.body, "mousemove", ContextualPopup.mouseOver.bindEventListener());
    });
}

ContextualPopup.isCtxPopElement = function (ele) {
    return (ele && DOM.getAncestorsByClassName(ele, "ContextualPopup", true).length);
}

ContextualPopup.mouseOver = function (e) {
    var target = e.target;
    var ctxPopupId = target.ctxPopupId;

    // did the mouse move out?
    if (!target || !ContextualPopup.isCtxPopElement(target) && ContextualPopup.ippu) {
        if (ContextualPopup.mouseInTimer || ContextualPopup.mouseOutTimer) return;

        ContextualPopup.mouseOutTimer = window.setTimeout(function () {
            ContextualPopup.mouseOut(e);
        }, 500);
        return;
    }

    // we're inside a ctxPopElement, cancel the mouseout timer
    if (ContextualPopup.mouseOutTimer) {
        window.clearTimeout(ContextualPopup.mouseOutTimer);
        ContextualPopup.mouseOutTimer = null;
    }

    if (!ctxPopupId)
    return;

    var cached = ContextualPopup.cachedResults[ctxPopupId + ""];

    // if we don't have cached data background request it
    if (!cached) {
        ContextualPopup.getInfo(target);
    }

    // start timer if it's not running
    if (! ContextualPopup.mouseInTimer && (! ContextualPopup.ippu || (
                                                                      ContextualPopup.currentId &&
                                                                      ContextualPopup.currentId != ctxPopupId))) {
        ContextualPopup.mouseInTimer = window.setTimeout(function () {
            ContextualPopup.showPopup(ctxPopupId);
        }, ContextualPopup.popupDelay);
    }
}

// if the popup was not closed by us catch it and handle it
ContextualPopup.popupClosed = function () {
    ContextualPopup.mouseOut();
}

ContextualPopup.mouseOut = function (e) {
    if (ContextualPopup.mouseInTimer)
        window.clearTimeout(ContextualPopup.mouseInTimer);
    if (ContextualPopup.mouseOutTimer)
        window.clearTimeout(ContextualPopup.mouseOutTimer);

    ContextualPopup.mouseInTimer = null;
    ContextualPopup.mouseOutTimer = null;
    ContextualPopup.currentId = null;

    ContextualPopup.hidePopup();
}

ContextualPopup.showPopup = function (ctxPopupId) {
    if (ContextualPopup.mouseInTimer) {
        window.clearTimeout(ContextualPopup.mouseInTimer);
    }
    ContextualPopup.mouseInTimer = null;

    if (ContextualPopup.ippu && (ContextualPopup.currentId && ContextualPopup.currentId == ctxPopupId)) {
        return;
    }

    ContextualPopup.currentId = ctxPopupId;

    ContextualPopup.constructIPPU(ctxPopupId);

    var ele = ContextualPopup.elements[ctxPopupId + ""];
    if (! ele) {
        return;
    }

    if (ContextualPopup.ippu) {
        // default is to auto-center, don't want that
        ContextualPopup.ippu.setAutoCenter(false, false);

        // pop up the box right under the element
        var dim = DOM.getAbsoluteDimensions(ele);
        if (!dim) return;

        ContextualPopup.ippu.setLocation(dim.absoluteLeft, dim.absoluteBottom);
        ContextualPopup.ippu.show();
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
    ippu.setCancelledCallback(ContextualPopup.popupClosed);
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
        if (data.url_userpic && data.url_userpic != ContextualPopup.elements[ctxPopupId].src) {
            var userpicContainer = document.createElement("div");
            var userpic = document.createElement("img");
            userpic.src = data.url_userpic;

            userpicContainer.appendChild(userpic);
            DOM.addClassName(userpicContainer, "Userpic");

            content.appendChild(userpicContainer);
        }

        // user name
        var displayName = document.createElement("div");
        displayName.innerHTML = "Name: " + data.display;
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
        if (data.is_requester) {
            relation.innerHTML = "This is you";
        } else {
            relation.innerHTML = data.username + " is " + (
                                                           data.is_friend ? "a friend" : "not a friend"
                                                           );
        }

        if (! data.is_friend) {
            // add friend link
            var addFriend = document.createElement("div");
            var addFriendLink = document.createElement("a");
            addFriendLink.href = data.url_addfriend;
            addFriendLink.innerHTML = "Add as friend";
            addFriend.appendChild(addFriendLink);
            DOM.addClassName(addFriend, "AddFriend");
            DOM.addEventListener(addFriendLink, "click", function (e) {
                Event.prep(e);
                Event.stop(e);
                return ContextualPopup.changeRelation(data, ctxPopupId, "addFriend"); });
            relation.appendChild(addFriend);
        } else {
            // remove friend link (omg!)
            var removeFriend = document.createElement("div");
            var removeFriendLink = document.createElement("a");
            removeFriendLink.href = data.url_delfriend;
            removeFriendLink.innerHTML = "Remove friend";
            removeFriend.appendChild(removeFriendLink);
            DOM.addClassName(removeFriend, "RemoveFriend");
            DOM.addEventListener(removeFriendLink, "click", function (e) {
                Event.prep(e);
                Event.stop(e);
                return ContextualPopup.changeRelation(data, ctxPopupId, "removeFriend"); });
            relation.appendChild(removeFriend);
        }

        DOM.addClassName(relation, "Relation");

        // set popup content
        content.appendChild(displayName);
        content.appendChild(profile);
        content.appendChild(journal);
        content.appendChild(relation);
        ippu.setContentElement(content);
    } else {
        ippu.setContent("Loading...");
    }

}

// ajax request to change relation
ContextualPopup.changeRelation = function (info, ctxPopupId, action) {
    if (!info) return true;

    var postData = {
        "target": info.username,
        "action": action,
        "ctxPopupId": ctxPopupId
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "url": "/tools/endpoints/changerelation.bml",
        "onError": ContextualPopup.gotError,
        "onData": ContextualPopup.changedRelation
    };

    HTTPReq.getJSON(opts);

    return false;
}

// callback from changing relation request
ContextualPopup.changedRelation = function (info) {
    log(inspect(info));
    var ctxPopupId = info.ctxPopupId + 0;
    if (!ctxPopupId) return;

    if (!info.success) return;

    if (ContextualPopup.cachedResults[ctxPopupId + ""]) {
        ContextualPopup.cachedResults[ctxPopupId + ""].is_friend = info.is_friend;
    }

    // if the popup is up, reload it
    ContextualPopup.renderPopup(ctxPopupId);
}

ContextualPopup.hidePopup = function (ctxPopupId) {
    // destroy popup for now
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }
}

// do ajax request of user info
ContextualPopup.getInfo = function (target) {
    var ctxPopupId = target.ctxPopupId;
    var username = target.username;
    var up_url = target.up_url;

    if (!(username || up_url))
        return;

    if (!ctxPopupId)
    return;

    if (ContextualPopup.currentRequests[ctxPopupId + ""]) {
        return;
    }

    ContextualPopup.currentRequests[ctxPopupId] = 1;

    if (!username) username = "";
    if (!up_url) up_url = "";

    var params = HTTPReq.formEncoded ({
        "user": username,
            "userpic_url": up_url,
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
