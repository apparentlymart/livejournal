var LJVAR;
if (! LJVAR) LJVAR = new Object();

// called by S2:
function setStyle (did, attr, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    if (de.style)
        de.style[attr] = val
}

// called by S2:
function setAttr (did, attr, classname) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.setAttribute(attr, classname);
}

function getXTR () {
    var xtr;
    var ex;

    if (typeof(XMLHttpRequest) != "undefined") {
        xtr = new XMLHttpRequest();
    } else {
        try {
            xtr = new ActiveXObject("Msxml2.XMLHTTP.4.0");
        } catch (ex) {
            try {
                xtr = new ActiveXObject("Msxml2.XMLHTTP");
            } catch (ex) {
            }
        }
    }
    return xtr;
}


// Utility/debugging functions
function htmlEncode( str ) {
        str.replace( /&/, "&amp;" );
        str.replace( /</, "&lt;" );
        str.replace( />/, "&gt;" );

        return str;
}

// hsv to rgb
// h, s, v = [0, 1), [0, 1], [0, 1]
// r, g, b = [0, 255], [0, 255], [0, 255]
function hsv_to_rgb (h, s, v)
{
    if (s == 0) {
	v *= 255;
	return [v,v,v];
    }

    h *= 6;
    var i = Math.floor(h);
    var f = h - i;
    var p = v * (1 - s);
    var q = v * (1 - s * f);
    var t = v * (1 - s * (1 - f));

    v = Math.floor(v * 255 + 0.5);
    t = Math.floor(t * 255 + 0.5);
    p = Math.floor(p * 255 + 0.5);
    q = Math.floor(q * 255 + 0.5);

    if (i == 0) return [v,t,p];
    if (i == 1) return [q,v,p];
    if (i == 2) return [p,v,t];
    if (i == 3) return [p,q,v];
    if (i == 4) return [t,p,v];
    return [v,p,q];
}

function stopEvent (e) {
    if (e.preventDefault)
        e.preventDefault();
    if (e.stopPropagation)
        e.stopPropagation();
    if ("cancelBubble" in e)
        e.cancelBubble = true;
    if ("returnValue" in e)
        e.returnValue = false;
    return false;
}

function scrollTop () {
    if (window.innerHeight)
        return window.pageYOffset;
    if (document.documentElement && document.documentElement.scrollTop)
        return document.documentElement.scrollTop;
    if (document.body)
        return document.body.scrollTop;
}

function scrollLeft () {
    if (window.innerWidth)
        return window.pageXOffset;
    if (document.documentElement && document.documentElement.scrollLeft)
        return document.documentElement.scrollLeft;
    if (document.body)
        return document.body.scrollLeft;
}

function getEventPos (e)
{
    var x = 0;
    var y = 0;
    if (!e) var e = window.event;
    if (e.pageX || e.pageY) {
        // useful case (relative to document)
        x = e.pageX;
        y = e.pageY;
    }
    else if (e.clientX || e.clientY) {
        // IE case (relative to viewport, so need scroll info)
        x = e.clientX + scrollLeft();
        y = e.clientY + scrollTop();
        //alert("case2: " + [x,y] +", " + [document.body.scrollLeft,document.body.scrollTop]);
    }
    return [x, y];
}

var curPopup = null;
var curPopup_id = 0;

function killPopup () {
    if (!curPopup)
        return true;

    var popup = curPopup;
    curPopup = null;

    var opp = 1.0;

    var fade = function () {
        opp -= 0.15;

        if (opp <= 0.1) {
            document.body.removeChild(popup);
        } else {
            popup.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            popup.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();

    return true;
}

var pendingReqs = new Object ();

function deleteComment (ditemid) {

    var hasopt = function (opt) {
        var el = document.getElementById("ljpopdel" + ditemid + opt);
        if (!el) return false;
        if (el.checked) return true;
        return false;
    };
    var opt_delthread = hasopt("thread");
    var opt_ban = hasopt("ban");
    var opt_spam = hasopt("spam");

    killPopup();

    var todel = document.getElementById("ljcmt" + ditemid);

    var col = 0;
    var pulse = 0;
    var is_deleted = 0;
    var is_error = 0;

    var xtr = getXTR();
    if (! xtr) {
        alert("no xtr now, but earlier?");
        return false;
    }
    pendingReqs[ditemid] = xtr;

    var state_callback = function () {
        if (xtr.readyState != 4)
             return;

        if (xtr.status == 200) {
            var val = eval(xtr.responseText);
            is_deleted = val;
            if (! is_deleted) is_error = 1;
        } else {
            alert("Error contacting server to delete comment.");
            is_error = 1;
        }
    };

    var error_callback = function () {
        alert("Error deleting " + ditemid);
        is_error = 1;
    };

    xtr.onreadystatechange = state_callback;
    //xtr.onerror = error_callback;
    xtr.open("POST", "/delcomment.bml?mode=js&journal=" + LJ_cmtinfo.journal + "&id=" + ditemid, true);
    var postdata = "confirm=1";
    if (opt_ban) postdata += "&ban=1";
    if (opt_spam) postdata += "&spam=1";
    if (opt_delthread) postdata += "&delthread=1";

    xtr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xtr.send(postdata);

    var flash = function () {
        var rgb = hsv_to_rgb(0, Math.cos((pulse + 1) / 2), 1);
        pulse += 3.14159 / 5;
        var color = "rgb(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ")";

        todel.style.border = "2px solid " + color;
        if (is_error) {
            todel.style.border = "";
            // and let timer expire
        } else if (is_deleted) {
            removeComment(ditemid, opt_delthread);
        } else {
            window.setTimeout(flash, 50);
        }
    };

    window.setTimeout(flash, 5);
}

function removeComment (ditemid, killChildren) {
    var todel = document.getElementById("ljcmt" + ditemid);
    if (todel) {
        todel.style.display = 'none';
    }
    if (killChildren) {
        var com = LJ_cmtinfo ? LJ_cmtinfo[ditemid] : null;
        for (var i = 0; i < com.rc.length; i++) {
            removeComment(com.rc[i], true);
        }
    }
}

function inspect( x )
{
    var t = "";
    for( var i in x )
    t += i + " = " + x[ i ] + "<br />";
    return t;
}

function createDeleteFunction (ae, dItemid) {
    return function (e) {
        if (!e) e = window.event;
        var FS = arguments.callee;

        var finalHeight = 100;

        //alert("dItemid callback = " + inspect(dItemid));
        if (e.shiftKey || (curPopup && curPopup_id != dItemid)) {
            killPopup();
        }

        var doIT = 0;
        // immediately delete on shift key
        if (e.shiftKey) {
            doIT = 1;
        } else {
            //doIT = confirm("Sure you wanna delete?");

            var com = LJ_cmtinfo ? LJ_cmtinfo[dItemid] : null;
            if (!com) return true;
            var jOwner = LJ_cmtinfo ? LJ_cmtinfo["journal"] : null;

            var pos = getEventPos(e);
            var lx = pos[0] + 5 - 250;
            if (lx < 5) lx = 5;
            var de;

            if (curPopup && curPopup_id == dItemid) {
                de = curPopup;
                de.style.left = lx + "px";
                de.style.top = (pos[1] + 5) + "px";
                return stopEvent(e);
            }

            de = document.createElement("div");
            de.style.color = "#000";
            de.style.height = "10px";
            de.style.overflow = "hidden";
            de.style.position = "absolute";
            de.style.left = lx + "px";
            de.style.top = (pos[1] + 5) + "px";
            de.style.width = "250px";
            de.style.background = "#e0e0e0";
            de.style.border = "2px solid black";
            de.style.padding = "3px";

            var inHTML = "<form style='display: inline' id='ljdelopts" + dItemid + "'><span style='font-face: Arial; font-size: 8pt'><b>Delete comment?</b><br />";
            var lbl;
            if (com.u != "" && com.u != jOwner) {
                lbl = "ljpopdel" + dItemid + "ban";
                inHTML += "<input type='checkbox' value='ban' id='" + lbl + "'> <label for='" + lbl + "'>Ban <b>" + com.u + "</b> from commenting</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (com.u != jOwner) {
                lbl = "ljpopdel" + dItemid + "spam";
                inHTML += "<input type='checkbox' value='spam' id='" + lbl + "'> <label for='" + lbl + "'>Mark this comment as spam</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (com.rc && com.rc.length) {
                lbl = "ljpopdel" + dItemid + "thread";
                inHTML += "<input type='checkbox' value='thread' id='" + lbl + "'> <label for='" + lbl + "'>Delete thread (all subcomments)</label><br />";
            } else {
                finalHeight -= 15;
            }
            inHTML += "<input type='button' value='Delete' onclick='deleteComment(" + dItemid + ");' /> <input type='button' value='Cancel' onclick='killPopup()' /></span><br /><span style='font-face: Arial; font-size: 8pt'><i>shift-click to delete without options</i></span></form>";
            de.innerHTML = inHTML;

            document.body.appendChild(de);
            //document.body.insertBefore(de, document.body.childNodes[0]);

            curPopup = de;
            curPopup_id = dItemid;

            var height = 10;
            var grow = function () {
                height += 7;
                if (height > finalHeight) {
                    de.style.height = null;
                    de.style.filter = "";
                    de.style.opacity = 1.0;
                } else {
                    de.style.height = height + "px";
                    window.setTimeout(grow, 20);
                }
            };
            grow();

        }

        if (doIT) {
            deleteComment(dItemid);
        }

        return stopEvent(e);
    }
}

function poofAt (pos) {
    var de = document.createElement("div");
    de.style.position = "absolute";
    de.style.background = "#FFF";
    de.style.overflow = "hidden";
    var opp = 1.0;

    var top = pos[1];
    var left = pos[0];
    var width = 5;
    var height = 5;
    document.body.appendChild(de);

    var fade = function () {
        opp -= 0.15;
        width += 10;
        height += 10;
        top -= 5;
        left -= 5;

        if (opp <= 0.1) {
            document.body.removeChild(de);
        } else {
            de.style.left = left + "px";
            de.style.top = top + "px";
            de.style.height = height + "px";
            de.style.width = width + "px";
            de.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            de.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();
}

function updateLink (ae, resObj, clickTarget) {
    ae.href = resObj.newurl;

    var userhook = window["userhook_" + resObj.mode + "_comment_ARG"];
    var did_something = 0;

    if (clickTarget && clickTarget.src && clickTarget.src == resObj.oldimage) {
        clickTarget.src = resObj.newimage;
        did_something = 1;
    }

    if (userhook) {
        userhook(resObj.id);
        did_something = 1;
    }

    // if all else fails, at least remove the link so they're not as confused
    if (! did_something) {
        if (ae && ae.style)
            ae.style.display = 'none';
        if (clickTarget && clickTarget.style)
            clickTarget.style.dispay = 'none';
    }

}

var tsInProg = new Object();  // dict of { ditemid => 1 }
function createModerationFunction (ae, dItemid) {
    return function (e) {
        if (!e) e = window.event;
        //alert(e.shiftKey ? "SUCKA SHIFTA!" : "SUCKA no shift");
        if (tsInProg[dItemid])
            return stopEvent(e);
        tsInProg[dItemid] = 1;

        var clickTarget = e.target;
        var clickPos = getEventPos(e);

        var de = document.createElement("img");
        de.style.position = "absolute";
        de.width = 17;
        de.height = 17;
        de.src = LJVAR.imgprefix + "/hourglass.gif";
        de.style.top = (clickPos[1] - 8) + "px";
        de.style.left = (clickPos[0] - 8) + "px";
        document.body.appendChild(de);

        var xtr = getXTR();
        var state_callback = function () {
            if (xtr.readyState != 4) return;

            document.body.removeChild(de);
            var rpcRes;

            if (xtr.status == 200) {
                var resObj = eval(xtr.responseText);
                if (resObj) {
                    poofAt(clickPos);
                    updateLink(ae, resObj, clickTarget);
                    tsInProg[dItemid] = 0;
                } else {
                    tsInProg[dItemid] = 0;
                }

            } else {
                alert("Error contacting server.");
                tsInProg[dItemid] = 0;
            }
        };


        xtr.onreadystatechange = state_callback;
        xtr.open("POST", ae.href + "&jsmode=1", true);

        var postdata = "confirm=Y";

        xtr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xtr.send(postdata);

        return stopEvent(e);
    };
}

function setup_ajax () {
    var ct = document.links.length;
    for (var i=0; i<ct; i++) {
        var ae = document.links[i];
        if (ae.href.indexOf("talkscreen.bml") != -1) {
            ae.onclick = createModerationFunction(ae, dItemid);

        } else if (ae.href.indexOf("delcomment.bml") != -1) {

            var findIDre = /id=(\d+)/;
            var reMatch = findIDre.exec(ae.href);
            if (! reMatch) return true;

            var dItemid = reMatch[1];
            var todel = document.getElementById("ljcmt" + dItemid);
            if (! todel) return true;

            ae.onclick = createDeleteFunction(ae, dItemid);
        }

    }
}

if (document.getElementById && getXTR()) {
    window.onload = setup_ajax;
}

