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

function deleteComment (ditemid, isS1) {
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
    var curJournal=(Site.currentJournal!="")?(Site.currentJournal):(LJ_cmtinfo.journal);
    var opts = {
        url: LiveJournal.getAjaxUrl('delcomment')+'?mode=js&journal=' + curJournal + '&id=' + ditemid,
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
            removeComment(ditemid, opt_delthread, isS1);
            if (opt_delauthor) {
                for (var item in LJ_cmtinfo) {
                    if (LJ_cmtinfo[item].u == LJ_cmtinfo[ditemid].u) {
                        removeComment(item, false, isS1);
                    }
                }
            }
        } else {
            window.setTimeout(flash, 50);
        }
    };

    window.setTimeout(flash, 5);
}

function removeComment (ditemid, killChildren, isS1) {
    if(isS1){
		var threadId = ditemid;

		getThreadJSON(threadId, function(result) {
			for( var i = 0; i < result.length; ++i ){
				jQuery("#ljcmtxt" + result[i].thread).html( result[i].html );
				if( result[i].thread in ExpanderEx.Collection)
					ExpanderEx.Collection[ result[i].thread ] = result[i].html;
			}
		});
    }
    else {
        var todel = document.getElementById("ljcmt" + ditemid);
        if (todel) {
            todel.style.display = 'none';

            var userhook = window["userhook_delete_comment_ARG"];
            if (userhook)
                userhook(ditemid);
        }
    }
    if (killChildren) {
        var com = LJ_cmtinfo[ditemid];
        for (var i = 0; i < com.rc.length; i++) {
            removeComment(com.rc[i], true, isS1);
        }
    }
}

function docClicked () {
    killPopup();

  // we didn't handle anything, who are we kidding
}

function createDeleteFunction (ae, dItemid, isS1) {
    return function (e) {
		e = jQuery.event.fix(e || window.event);

        var finalHeight = 115;

        if (e.shiftKey || (curPopup && curPopup_id != dItemid)) {
            killPopup();
        }

        var doIT = 0;
        // immediately delete on shift key
        if (e.shiftKey) {
            doIT = 1;
			deleteComment(dItemid, isS1);
        } else {
            if (! LJ_cmtinfo)
                return true;

            var com = LJ_cmtinfo[dItemid];
            var remoteUser = LJ_cmtinfo["remote"];
            if (!com || !remoteUser)
                return true;
            var canAdmin = LJ_cmtinfo["canAdmin"];
			
			var pos_offset = jQuery(ae).position(),
				offset = jQuery(ae).offset(),
				pos_x = e.pageX + pos_offset.left - offset.left,
				top = e.pageY + pos_offset.top - offset.top + 5,
				left = Math.max(pos_x + 5 - 250, 5),
				$window = jQuery(window);
			
			//calc with viewport
			if ($window.scrollLeft() > left + offset.left - pos_offset.left) {
				left = $window.scrollLeft() + pos_offset.left - offset.left;
			}
			
			if (curPopup && curPopup_id == dItemid) {
				//calc with viewport
				top = Math.min(top, $window.height() + $window.scrollTop() - jQuery(curPopup).outerHeight() + pos_offset.top - offset.top);
				curPopup.style.left = left + 'px';
				curPopup.style.top = top + 'px';
				
				return Event.stop(e);
			}
			
			var de = jQuery('<div class="ljcmtmanage" style="text-align:left;position:absolute;visibility:hidden;width:250px;left:0;top:0;z-index:3"></div>')
						.click(function(e){
							e.stopPropagation()
						});
			
            var inHTML = "<form style='display: inline' id='ljdelopts" + dItemid + "'><span style='font-face: Arial; font-size: 8pt'><b>Delete comment?</b><br />";
            var lbl;
            if (com.username != "" && com.username != remoteUser && canAdmin) {
                lbl = "ljpopdel" + dItemid + "ban";
                inHTML += "<input type='checkbox' name='ban' id='" + lbl + "'> <label for='" + lbl + "'>Ban <b>" + com.u + "</b> from commenting</label><br />";
            } else {
                finalHeight -= 15;
            }

            if (remoteUser != com.username) {
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
            if (canAdmin&&com.username) {
                lbl = "ljpopdel" + dItemid + "author";
                inHTML += "<input type='checkbox' name='delauthor' id='" + lbl + "'> <label for='" + lbl + "'>Delete all <b>" + (com.username == remoteUser ? 'my' : com.u) + "</b> comments in this post</label><br />";
            } else {
                finalHeight -= 15;
            }

            inHTML += "<input type='button' value='Delete' onclick='deleteComment(" + dItemid + ", " + isS1.toString() + ");' /> <input type='button' value='Cancel' onclick='killPopup()' /></span><br /><span style='font-face: Arial; font-size: 8pt'><i>shift-click to delete without options</i></span></form>";
			
			de.html(inHTML).insertAfter(ae);
			
			//calc with viewport
			top = Math.min(top, $window.height() + $window.scrollTop() - de.outerHeight() + pos_offset.top - offset.top);
			
			de.css({
				left: left,
				top: top,
				height: 10,
				visibility: 'visible',
				overflow: 'hidden'
			});
			
			curPopup = de[0];
			curPopup_id = dItemid;
			
			var height = 10;
			var grow = function () {
				height += 7;
				if (height > finalHeight) {
					de.height('auto');
				} else {
					de.height(height);
					window.setTimeout(grow, 20);
				}
			}
			grow();
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

var tsInProg = {}  // dict of { ditemid => 1 }
function createModerationFunction(ae, dItemid, isS1)
{
	return function(e)
	{
		var e = jQuery.event.fix(e || window.event);
			pos = { x: e.pageX, y: e.pageY },
			postUrl = ae.href.replace(/.+talkscreen\.bml/, LiveJournal.getAjaxUrl('talkscreen')),
			hourglass = jQuery(e).hourglass()[0];

		var xhr = jQuery.post(postUrl + '&jsmode=1',
			{
				confirm: 'Y',
				lj_form_auth: LJ_cmtinfo.form_auth
			},
			function(json)
			{
				tsInProg[dItemid] = 0;
				var comms_ary = [dItemid]
				var map_comms = function(id)
				{
					var i = -1, new_id;
					while(new_id = LJ_cmtinfo[id].rc[++i])
					{
						if (LJ_cmtinfo[new_id].full) {
							comms_ary.push(new_id);
							map_comms(String(new_id));
						}
					}
				}
				
				// check rc for no comments page
				if (LJ_cmtinfo[dItemid].rc) {
					if (/mode=(un)?freeze/.test(ae.href)) {
						map_comms(dItemid);
					}
					var ids = '#ljcmt' + comms_ary.join(',#ljcmt');
				} else {
					var rpcRes;
					eval(json);
					updateLink(ae, rpcRes, ae.getElementsByTagName('img')[0]);
					// /tools/recent_comments.bml
					if (document.getElementById('ljcmtbar'+dItemid)) {
						var ids = '#ljcmtbar'+dItemid;
					}
					// ex.: portal/
					else {
						hourglass.hide();
						poofAt(pos);
						return;
					}
				}

				if(isS1){
					var newNode, showExpand, j, children;
					var threadId = dItemid,
						threadExpanded = !!(LJ_cmtinfo[ threadId ].oldvars && LJ_cmtinfo[ threadId ].full);
						populateComments = function(result){
							for( var i = 0; i < result.length; ++i ){
								if( LJ_cmtinfo[ result[i].thread ].full ){
									showExpand = !( 'oldvars' in LJ_cmtinfo[ result[i].thread ]);

									//still show expand button if children comments are folded
									if( !showExpand ) {
										children  = LJ_cmtinfo[ result[i].thread ].rc;

										for( j = 0; j < children.length;  ++j ) {
											if( !( 'oldvars' in LJ_cmtinfo[ children[j] ] ) ) {
												showExpand = true;
											}
										}
									}

									newNode = ExpanderEx.prepareCommentBlock(
											result[i].html,
											result[ i ].thread,
											showExpand
									);

									setupAjax( newNode[0], isS1 );
									jQuery("#ljcmtxt" + result[i].thread).replaceWith( newNode );
								}
							}
							hourglass.hide();
							poofAt(pos);
						};

					getThreadJSON(threadId, function(result) {
						//if comment is expanded we need to fetch it's collapsed state additionally
						if( threadExpanded && LJ_cmtinfo[ threadId ].oldvars.full )
						{
							getThreadJSON( threadId, function(result2){
								ExpanderEx.Collection[ threadId ] = ExpanderEx.prepareCommentBlock( result2[0].html, threadId, true ).html();
								populateComments( result );
							}, true, true );
						}
						else
							populateComments( result );
					}, false, !threadExpanded);
				}
				else {
					// modified jQuery.fn.load
					jQuery.ajax({
						url: location.href,
						type: 'GET',
						dataType: 'html',
						complete: function(res, status) {
							// If successful, inject the HTML into all the matched elements
							if (status == 'success' || status == 'notmodified') {
								// Create a dummy div to hold the results
								var nodes = jQuery('<div/>')
									// inject the contents of the document in, removing the scripts
									// to avoid any 'Permission Denied' errors in IE
									.append(res.responseText.replace(/<script(.|\s)*?\/script>/gi, ''))
									// Locate the specified elements
									.find(ids)
									.each(function(){
										var id = this.id.replace(/[^0-9]/g, '');
										if (LJ_cmtinfo[id].expanded) {
											var expand = this.innerHTML.match(/Expander\.make\(.+?\)/)[0];
											(function(){
												eval(expand);
											}).apply(document.createElement('a'));
										} else {
											jQuery('#'+this.id).replaceWith(this);
											setupAjax(this, isS1);
										}
									});
								hourglass.hide();
								poofAt(pos);
							}
						}
					});
				}
			}
		);
		
		return false;
	}
}

function setupAjax (node, isS1) {
    var links = node ? node.getElementsByTagName('a') : document.links,
        rex_id = /id=(\d+)/,
        i = -1, ae;

    isS1 = isS1 || false;
    while (links[++i]) {
        ae = links[i];
        if (ae.href.indexOf('talkscreen.bml') != -1) {
            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;

            ae.onclick = createModerationFunction(ae, id, isS1);
        } else if (ae.href.indexOf('delcomment.bml') != -1) {
            if (LJ_cmtinfo && LJ_cmtinfo.disableInlineDelete) continue;

            var reMatch = rex_id.exec(ae.href);
            if (!reMatch) continue;

            var id = reMatch[1];
            if (!document.getElementById('ljcmt' + id)) continue;

            ae.onclick = createDeleteFunction(ae, id, isS1);
        }
    }
}

function getThreadJSON(threadId, success, getSingle)
{
    var postid = location.href.match(/\/(\d+).html/)[1],
        params = [
            'journal=' + Site.currentJournal,
            'itemid=' + postid,
            'thread=' + threadId,
            'depth=' + LJ_cmtinfo[ threadId ].depth
        ];
    if( getSingle)
        params.push( 'single=1' );

    var url = LiveJournal.getAjaxUrl('get_thread') + '?' + params.join( '&' );
    jQuery.get( url, success, 'json' );
}

jQuery(function(){setupAjax( false, ("is_s1" in LJ_cmtinfo ) )});

DOM.addEventListener(document, 'click', docClicked);
document.write("<style> div.ljcmtmanage { color: #000; background: #e0e0e0; border: 2px solid #000; padding: 3px; }</style>");
