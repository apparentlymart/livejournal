// called by S2:
function setStyle (did, attr, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    if (de.style)
        de.style[attr] = val
}

// called by S2:
function setInner (did, val) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.innerHTML = val;
}

// called by S2:
function hideElement (did) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.style.display = 'none';
}

// called by S2:
function setAttr (did, attr, classname) {
    if (! document.getElementById) return;
    var de = document.getElementById(did);
    if (! de) return;
    de.setAttribute(attr, classname);
}

// called from Page:
function multiformSubmit (form, txt) {
    var sel_val = form.mode.value;
    if (!sel_val) {
        alert(txt.no_action);
        return false;
    }

    if (sel_val.substring(0, 4) == 'all:') { // mass action
        return;
    }

    var i = -1, has_selected = false; // at least one checkbox
    while (form[++i]) {
        if (form[i].name.substring(0, 9) == 'selected_' && form[i].checked) {
            has_selected = true;
            break;
        }
    }
    if (!has_selected) {
        alert(txt.no_comments);
        return false;
    }

    if (sel_val == 'delete' || sel_val == 'deletespam') {
        return confirm(txt.conf_delete);
    }
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

    // let me explain this.  Opera 8 does XMLHttpRequest, but not setRequestHeader.
    // no problem, we thought:  we'll test for setRequestHeader and if it's not present
    // then fall back to the old behavior (treat it as not working).  BUT --- IE6 won't
    // let you even test for setRequestHeader without throwing an exception (you need
    // to call .open on the .xtr first or something)
    try {
        if (xtr && ! xtr.setRequestHeader)
            xtr = null;
    } catch (ex) { }

    return xtr;
}

function positionedOffset(element) {
  var valueT = 0, valueL = 0;
  do {
    valueT += element.offsetTop  || 0;
    valueL += element.offsetLeft || 0;
    element = element.offsetParent;
    if (element) {
      if (element.tagName.toUpperCase() == 'BODY') break;
      var p = DOM.getStyle(element, 'position');
      if (p !== 'static') break;
    }
  } while (element);
  return {x: valueL, y:valueT};
}

// push new element 'ne' after sibling 'oe' old element
function addAfter (oe, ne) {
    if (oe.nextSibling) {
        oe.parentNode.insertBefore(ne, oe.nextSibling);
    } else {
        oe.parentNode.appendChild(ne);
    }
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

function getElementPos (obj)
{
    var pos = new Object();
    if (!obj)
        return null;

    var it;

    it = obj;
    pos.x = 0;
    if (it.offsetParent) {
	while (it.offsetParent) {
	    pos.x += it.offsetLeft;
	    it = it.offsetParent;
	}
    }
    else if (it.x)
	pos.x += it.x;

    it = obj;
    pos.y = 0;
    if (it.offsetParent) {
	while (it.offsetParent) {
	    pos.y += it.offsetTop;
	    it = it.offsetParent;
	}
    }
    else if (it.y)
	pos.y += it.y;

    return pos;
}

// returns the mouse position of the event, or failing that, the top-left
// of the event's target element.  (or the fallBack element, which takes
// precendence over the event's target element if specified)
function getEventPos (e, fallBack)
{
    var pos = { x:0, y:0 };

    if (!e) var e = window.event;
    if (e.pageX && e.pageY) {
        // useful case (relative to document)
        pos.x = e.pageX;
        pos.y = e.pageY;
    }
    else if (e.clientX && e.clientY) {
        // IE case (relative to viewport, so need scroll info)
        pos.x = e.clientX + scrollLeft();
        pos.y = e.clientY + scrollTop();
    } else {
        var targ = fallBack || getTarget(e);
        var pos = getElementPos(targ);
    }
    return pos;
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
            popup.parentNode.removeChild(popup);
        } else {
            popup.style.filter = "alpha(opacity=" + Math.floor(opp * 100) + ")";
            popup.style.opacity = opp;
            window.setTimeout(fade, 20);
        }
    };
    fade();

    return true;
}

function deleteComment (ditemid) {
    killPopup();

    var form = $('ljdelopts' + ditemid),
        todel = $('ljcmt' + ditemid),
        opt_delthread = opt_delauthor =
        is_deleted = is_error = false,
        pulse = 0;

    var postdata = 'confirm=1';
    if (form){ 
    	if (form.ban && form.ban.checked) postdata += '&ban=1';
    	if (form.spam && form.spam.checked) postdata += '&spam=1';
    	if (form.delthread && form.delthread.checked) {
        	postdata += '&delthread=1';
        	opt_delthread = true;
   	 }
    	if (form.delauthor && form.delauthor.checked) {
        	postdata += '&delauthor=1';
        	opt_delauthor = true;
    	}
    }
    postdata += '&lj_form_auth=' + LJ_cmtinfo.form_auth;
    var opts = {
        url: LiveJournal.getAjaxUrl('delcomment')+'?mode=js&journal=' + Site.currentJournal + '&id=' + ditemid,
        data: postdata,
        method: 'POST',
        onData: function(data) {
            is_deleted = !!data;
            is_error = !is_deleted;
        },
        onError: function() {
          alert('Error deleting ' + ditemid);
          is_error = true;
        }
    }

    HTTPReq.getJSON(opts);

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
            if (opt_delauthor) {
                for (var item in LJ_cmtinfo) {
                    if (LJ_cmtinfo[item].u == LJ_cmtinfo[ditemid].u) {
                        removeComment(item);
                    }
                }
            }
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

        var userhook = window["userhook_delete_comment_ARG"];
        if (userhook)
            userhook(ditemid);
    }
    if (killChildren) {
        var com = LJ_cmtinfo[ditemid];
        for (var i = 0; i < com.rc.length; i++) {
            removeComment(com.rc[i], true);
        }
    }
}

function docClicked () {
    killPopup();

  // we didn't handle anything, who are we kidding
}

function createDeleteFunction (ae, dItemid) {
    return function (e) {
        if (!e) e = window.event;
        var FS = arguments.callee;

        var finalHeight = 115;

        if (e.shiftKey || (curPopup && curPopup_id != dItemid)) {
            killPopup();
        }

        var doIT = 0;
        // immediately delete on shift key
        if (e.shiftKey) {
            doIT = 1;
        } else {
            if (! LJ_cmtinfo)
                return true;

            var com = LJ_cmtinfo[dItemid];
            var remoteUser = LJ_cmtinfo["remote"];
            if (!com || !remoteUser)
                return true;
            var canAdmin = LJ_cmtinfo["canAdmin"];

            var clickTarget = getTarget(e);

            var pos = getEventPos(e);
            var pos_offset = positionedOffset(ae)
            var diff_x = DOM.findPosX(ae) - pos_offset.x
            var diff_y = DOM.findPosY(ae) - pos_offset.y

            var lx = pos.x - diff_x + 5 - 250;
            if (lx < 5) lx = 5;
            var de;

            if (curPopup && curPopup_id == dItemid) {
                de = curPopup;
                de.style.left = lx + "px";
                de.style.top = (pos.y - diff_y + 5) + "px";
                return Event.stop(e);
            }

            de = document.createElement("div");
            de.style.textAlign = "left";
            de.className = 'ljcmtmanage';
            de.style.height = "10px";
            de.style.overflow = "hidden";
            de.style.position = "absolute";
            de.style.left = lx + "px";
            de.style.top = (pos.y - diff_y + 5) + "px";
            de.style.width = "250px";
            de.style.zIndex = 3;
            DOM.addEventListener(de, 'click', function (e) {
                Event.stopPropagation(e);
                return true;
            });

            var inHTML = "<form style='display: inline' id='ljdelopts" + dItemid + "'><span style='font-face: Arial; font-size: 8pt'><b>Delete comment?</b><br />";
            var lbl;
            if (remoteUser != "" && com.u != "" && com.u != remoteUser && canAdmin) {
                lbl = "ljpopdel" + dItemid + "ban";
                inHTML += "<input type='checkbox' name='ban' id='" + lbl + "'> <label for='" + lbl + "'>Ban <b>" + com.u + "</b> from commenting</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (remoteUser != "" && remoteUser != com.u) {
                lbl = "ljpopdel" + dItemid + "spam";
                inHTML += "<input type='checkbox' name='spam' id='" + lbl + "'> <label for='" + lbl + "'>Mark this comment as spam</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (com.rc && com.rc.length && canAdmin) {
                lbl = "ljpopdel" + dItemid + "thread";
                inHTML += "<input type='checkbox' name='delthread' id='" + lbl + "'> <label for='" + lbl + "'>Delete thread (all subcomments)</label><br />";
            } else {
                finalHeight -= 15;
            }
            if (canAdmin&&com.u) {
                lbl = "ljpopdel" + dItemid + "author";
                inHTML += "<input type='checkbox' name='delauthor' id='" + lbl + "'> <label for='" + lbl + "'>Delete all <b>" + (com.u == remoteUser ? 'my' : com.u) + "</b> comments in this post</label><br />";
            } else {
                finalHeight -= 15;
            }

            inHTML += "<input type='button' value='Delete' onclick='deleteComment(" + dItemid + ");' /> <input type='button' value='Cancel' onclick='killPopup()' /></span><br /><span style='font-face: Arial; font-size: 8pt'><i>shift-click to delete without options</i></span></form>";
            de.innerHTML = inHTML;

            // we do this so keyboard tab order is correct:
            addAfter(ae, de);

            curPopup = de;
            curPopup_id = dItemid;

            var height = 10;
            var grow = function () {
                height += 7;
                if (height > finalHeight) {
                    de.style.height = "";
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

        Event.stop(e);
    }
}

function poofAt (pos) {
    var de = document.createElement("div");
    de.style.position = "absolute";
    de.style.background = "#FFF";
    de.style.overflow = "hidden";
    var opp = 1.0;

    var top = pos.y;
    var left = pos.x;
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
            de.parentNode.removeChild(de);
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

function getTarget (ev) {
    var target;
    if (ev.target)
        target = ev.target;
    else if (ev.srcElement)
        target = ev.srcElement;

    // Safari bug:
    if (target && target.nodeType == 3)
        target = target.parentNode;

    return target;
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

        if (tsInProg[dItemid])
            return Event.preventDefault(e);
        tsInProg[dItemid] = 1;

        var clickTarget = getTarget(e);

        var imgTarget;
        var imgs = ae.getElementsByTagName("img");
        if (imgs.length)
            imgTarget = imgs[0]

        if (! clickTarget || typeof(clickTarget) != "object")
            return true;

        var clickPos = getEventPos(e);

        var de = document.createElement("img");
        de.style.position = "absolute";
        de.width = 17;
        de.height = 17;
        de.src = Site.imgprefix + "/hourglass.gif";
        de.style.top = (clickPos.y - 8) + "px";
        de.style.left = (clickPos.x - 8) + "px";
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
                    updateLink(ae, resObj, imgTarget);
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

        var postUrl = ae.href.replace(/.+talkscreen\.bml/, "/" + Site.currentJournal + "/__rpc_talkscreen");

        //var postUrl = ae.href;
        xtr.open("POST", postUrl + "&jsmode=1", true);

        var postdata = "confirm=Y&lj_form_auth=" + LJ_cmtinfo.form_auth;

        xtr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xtr.send(postdata);

        Event.preventDefault(e);
    };
}

function setupAjax (node) {
    var links = node ? node.getElementsByTagName('a') : document.links,
        rex_id = /id=(\d+)/,
        i = -1, ae;

    while (links[++i]) {
        ae = links[i];
        if (ae.href.indexOf('talkscreen.bml') != -1) {
            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;

            ae.onclick = createModerationFunction(ae, id);
        } else if (ae.href.indexOf('delcomment.bml') != -1) {
            if (LJ_cmtinfo && LJ_cmtinfo.disableInlineDelete) continue;

            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;

            ae.onclick = createDeleteFunction(ae, id);
        }
    }
}



LiveJournal.register_hook('page_load', function () {
    setupAjax()
});
DOM.addEventListener(document, 'click', docClicked);
document.write("<style> div.ljcmtmanage { color: #000; background: #e0e0e0; border: 2px solid #000; padding: 3px; }</style>");
