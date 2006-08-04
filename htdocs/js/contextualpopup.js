var ContextualPopup = new Object;

ContextualPopup.popupDelay  = 500;
ContextualPopup.hideDelay   = 250;
ContextualPopup.disableAJAX = false;
ContextualPopup.debug       = false;

ContextualPopup.cachedResults   = {};
ContextualPopup.currentRequests = {};
ContextualPopup.mouseInTimer    = null;
ContextualPopup.mouseOutTimer   = null;
ContextualPopup.currentId       = null;
ContextualPopup.hourglass       = null;
ContextualPopup.elements        = {};

ContextualPopup.setup = function (e) {
    // don't do anything if no remote
    if (!LJVAR || !LJVAR.has_remote || !LJVAR.ctx_popup) return;

    // attach to all ljuser head icons
    var domObjects = document.getElementsByTagName("*");
    var ljusers = DOM.filterElementsByClassName(domObjects, "ljuser") || [];

    var userElements = [];
    ljusers.forEach(function (ljuser) {
        var nodes = ljuser.getElementsByTagName("img");
        for (var i=0; i < nodes.length; i++) {
            var node = nodes.item(i);

            // if the parent (a tag with link to userinfo) has userid in its URL, then
            // this is an openid user icon and we should use the userid
            var parent = node.parentNode;
            var userid;
            if (parent && (userid = parent.href.match(/\?userid=(\d+)/i)))
                node.userid = userid[1];
            else
                node.username = ljuser.getAttribute("lj:user");

            if (!node.username && !node.userid) continue;

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
    if (!target || !ContextualPopup.isCtxPopElement(target)) {
        if (ContextualPopup.mouseInTimer) {
            window.clearTimeout(ContextualPopup.mouseInTimer);
            ContextualPopup.mouseInTimer = null;
        };

        if (ContextualPopup.ippu) {
            if (ContextualPopup.mouseInTimer || ContextualPopup.mouseOutTimer) return;

            ContextualPopup.mouseOutTimer = window.setTimeout(function () {
                ContextualPopup.mouseOut(e);
            }, ContextualPopup.hideDelay);
            return;
        }
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
    var data = ContextualPopup.cachedResults[ctxPopupId + ""];

    if (! ele || (data && data.noshow)) {
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

    var ippu = new IPPU();
    ippu.init();
    ippu.setTitlebar(false);
    ippu.setFadeOut(true);
    ippu.setFadeIn(true);
    ippu.setFadeSpeed(15);
    ippu.setDimensions("auto", "auto");
    ippu.addClass("ContextualPopup");
    ippu.setCancelledCallback(ContextualPopup.popupClosed);
    ContextualPopup.ippu = ippu;

    ContextualPopup.renderPopup(ctxPopupId);
}

ContextualPopup.renderPopup = function (ctxPopupId) {
    var ippu = ContextualPopup.ippu;

    if (!ippu)
    return;

    if (ctxPopupId) {
        var data = ContextualPopup.cachedResults[ctxPopupId];

        if (!data) {
            ippu.setContent("<div class='Inner'>Loading...</div>");
            return;
        } else if (!data.username || !data.success || data.noshow) {
            ippu.hide();
            return;
        }

        var username = data.display_username;

        var inner = document.createElement("div");
        DOM.addClassName(inner, "Inner");

        var content = document.createElement("div");
        DOM.addClassName(content, "Content");

        var bar = document.createElement("span");
        bar.innerHTML = " | ";

        // userpic
        if (data.url_userpic && data.url_userpic != ContextualPopup.elements[ctxPopupId].src) {
            var userpicContainer = document.createElement("div");
            var userpic = document.createElement("img");
            userpic.src = data.url_userpic;
            userpic.width = data.userpic_w;
            userpic.height = data.userpic_h;

            userpicContainer.appendChild(userpic);
            DOM.addClassName(userpicContainer, "Userpic");

            inner.appendChild(userpicContainer);
        }

        inner.appendChild(content);

        // relation
        var relation = document.createElement("div");
        if (data.is_comm) {
            if (data.is_member)
                relation.innerHTML = "You are a member of " + username;
            else if (data.is_friend)
                relation.innerHTML = "You are watching " + username;
            else
                relation.innerHTML = username;
        } else if (data.is_syndicated) {
            if (data.is_friend)
                relation.innerHTML = "You are subscribed to " + username;
            else
                relation.innerHTML = username;
        } else {
            if (data.is_requester) {
                relation.innerHTML = "This is you";
            } else {
                var label = username + " ";

                if (data.is_friend_of) {
                    if (data.is_friend)
                        label += "is your mutual friend";
                    else
                        label += "lists you as a friend";
                } else {
                    if (data.is_friend)
                        label += "is your friend";
                }

                relation.innerHTML = label;
            }
        }
        DOM.addClassName(relation, "Relation");
        content.appendChild(relation);

        // add site-specific content here
        var extraContent = LiveJournal.run_hook("ctxpopup_extrainfo", data);
        if (extraContent) {
            content.appendChild(extraContent);
        }

        // member of community
        if (data.is_comm) {
            var membership      = document.createElement("span");
            var membershipLink  = document.createElement("a");

            var membership_action = data.is_member ? "leave" : "join";

            if (data.is_member) {
                membershipLink.href = data.url_leavecomm;
                membershipLink.innerHTML = "Leave";
            } else {
                membershipLink.href = data.url_joincomm;
                membershipLink.innerHTML = "Join community";
            }

            if (!ContextualPopup.disableAJAX) {
                DOM.addEventListener(membershipLink, "click", function (e) {
                    Event.prep(e);
                    Event.stop(e);
                    return ContextualPopup.changeRelation(data, ctxPopupId, membership_action, e); });
            }

            membership.appendChild(membershipLink);
            content.appendChild(membership);
        }

        // friend
        var friend;
        if (! data.is_requester) {
            friend = document.createElement("span");

            if (! data.is_friend) {
                // add friend link
                var addFriend = document.createElement("span");
                var addFriendLink = document.createElement("a");
                addFriendLink.href = data.url_addfriend;

                if (data.is_comm)
                    addFriendLink.innerHTML = "Watch community";
                else if (data.is_syndicated)
                    addFriendLink.innerHTML = "Subscribe to feed";
                else
                    addFriendLink.innerHTML = "Add friend";

                addFriend.appendChild(addFriendLink);
                DOM.addClassName(addFriend, "AddFriend");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(addFriendLink, "click", function (e) {
                        Event.prep(e);
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "addFriend", e); });
                }

                friend.appendChild(addFriend);
            } else {
                // remove friend link (omg!)
                var removeFriend = document.createElement("span");
                var removeFriendLink = document.createElement("a");
                removeFriendLink.href = data.url_addfriend;

                if (data.is_comm)
                    removeFriendLink.innerHTML = "Stop watching";
                else if (data.is_syndicated)
                    removeFriendLink.innerHTML = "Unsubscribe";
                else
                    removeFriendLink.innerHTML = "Remove friend";

                removeFriend.appendChild(removeFriendLink);
                DOM.addClassName(removeFriend, "RemoveFriend");

                if (!ContextualPopup.disableAJAX) {
                    DOM.addEventListener(removeFriendLink, "click", function (e) {
                        Event.stop(e);
                        return ContextualPopup.changeRelation(data, ctxPopupId, "removeFriend", e); });
                }

                friend.appendChild(removeFriend);
            }

            DOM.addClassName(relation, "FriendStatus");
        }

        // add a bar between stuff if we have community actions
        if (data.is_comm)
            content.appendChild(bar.cloneNode(true));

        if (friend)
            content.appendChild(friend);

        // break
        if (!data.is_requester) content.appendChild(document.createElement("br"));

        // view label
        var viewLabel = document.createElement("span");
        viewLabel.innerHTML = "View: ";
        content.appendChild(viewLabel);

        // journal
        if (data.is_person || data.is_comm || data.is_syndicated) {
            var journalLink = document.createElement("a");
            journalLink.href = data.url_journal;

            if (data.is_person)
                journalLink.innerHTML = "Journal";
            else if (data.is_comm)
                journalLink.innerHTML = "Community";
            else if (data.is_syndicated)
                journalLink.innerHTML = "Feed";

            content.appendChild(journalLink);
            content.appendChild(bar.cloneNode(true));
        }

        // profile
        var profileLink = document.createElement("a");
        profileLink.href = data.url_profile;
        profileLink.innerHTML = "Profile";
        content.appendChild(profileLink);

        // clearing div
        var clearingDiv = document.createElement("div");
        DOM.addClassName(clearingDiv, "ljclear");
        clearingDiv.innerHTML = "&nbsp;";
        content.appendChild(clearingDiv);

        ippu.setContentElement(inner);
    }
}

// ajax request to change relation
ContextualPopup.changeRelation = function (info, ctxPopupId, action, evt) {
    if (!info) return true;

    var postData = {
        "target": info.username,
        "action": action
    };

    // get the authtoken
    var authtoken = info[action + "_authtoken"];
    if (!authtoken) log("no auth token for action" + action);
    postData.auth_token = authtoken;

    // needed on journal subdomains
    var url = LJVAR.currentJournal ? "/" + LJVAR.currentJournal + "/__rpc_changerelation" : "/__rpc_changerelation";

    // callback from changing relation request
    var changedRelation = function (data) {
        if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

        if (data.error) {
            ContextualPopup.showNote(data.error, ctxPopupId);
            return;
        }

        if (data.note)
        ContextualPopup.showNote(data.note, ctxPopupId);

        if (!data.success) return;

        if (ContextualPopup.cachedResults[ctxPopupId + ""]) {
            var updatedProps = ["is_friend", "is_member"];
            updatedProps.forEach(function (prop) {
                ContextualPopup.cachedResults[ctxPopupId + ""][prop] = data[prop];
            });
        }

        // if the popup is up, reload it
        ContextualPopup.renderPopup(ctxPopupId);
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "url": url,
        "onError": ContextualPopup.gotError,
        "onData": changedRelation
    };

    // do hourglass at mouse coords
    var mouseCoords = DOM.getAbsoluteCursorPosition(evt);
    if (!ContextualPopup.hourglass && mouseCoords) {
        ContextualPopup.hourglass = new Hourglass();
        ContextualPopup.hourglass.init(null, "lj_hourglass");
        ContextualPopup.hourglass.add_class_name("ContextualPopup"); // so mousing over hourglass doesn't make ctxpopup think mouse is outside
        ContextualPopup.hourglass.hourglass_at(mouseCoords.x, mouseCoords.y);
    }

    HTTPReq.getJSON(opts);

    return false;
}

// create a little popup to notify the user of something
ContextualPopup.showNote = function (note, ctxPopupId) {
    var ele;

    if (ContextualPopup.ippu) {
        // pop up the box right under the element
        ele = ContextualPopup.ippu.getElement();
    } else {
        if (ctxPopupId) {
            var ele = ContextualPopup.elements[ctxPopupId + ""];
        }
    }

    LJ_IPPU.showNote(note, ele);
}

ContextualPopup.hidePopup = function (ctxPopupId) {
    if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

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
    var userid = target.userid;
    var up_url = target.up_url;

    if (!ctxPopupId)
    return;

    if (ContextualPopup.currentRequests[ctxPopupId + ""]) {
        return;
    }

    ContextualPopup.currentRequests[ctxPopupId] = 1;

    if (!username) username = "";
    if (!userid) userid = 0;
    if (!up_url) up_url = "";

    var params = HTTPReq.formEncoded ({
        "user": username,
            "userid": userid,
            "userpic_url": up_url,
            "mode": "getinfo"
    });

    // needed on journal subdomains
    var url = LJVAR.currentJournal ? "/" + LJVAR.currentJournal + "/__rpc_ctxpopup" : "/__rpc_ctxpopup";

    // got data callback
    var gotInfo = function (data) {
        if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

        ContextualPopup.cachedResults[ctxPopupId] = data;

        if (data.error) {
            if (data.noshow) return;

            ContextualPopup.showNote(data.error, ctxPopupId);
            return;
        }

        if (data.note)
        ContextualPopup.showNote(data.note, data.ctxPopupId);

        ContextualPopup.currentRequests[ctxPopupId] = null;

        ContextualPopup.renderPopup(ctxPopupId);

        // expire cache after 5 minutes
        setTimeout(function () {
            ContextualPopup.cachedResults[ctxPopupId] = null;
        }, 5 * 60 * 1000);
    };

    HTTPReq.getJSON({
        "url": url,
            "method" : "GET",
            "data": params,
            "onData": gotInfo,
            "onError": ContextualPopup.gotError
            });
}

ContextualPopup.hideHourglass = function () {
    if (ContextualPopup.hourglass) {
        ContextualPopup.hourglass.hide();
        ContextualPopup.hourglass = null;
    }
}

ContextualPopup.gotError = function (err) {
    if (ContextualPopup.hourglass) ContextualPopup.hideHourglass();

    if (ContextualPopup.debug)
        ContextualPopup.showNote("Error: " + err);
}

// when page loads, set up contextual popups
DOM.addEventListener(window, "load", ContextualPopup.setup);
