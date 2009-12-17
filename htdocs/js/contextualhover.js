LJWidget = new Class(Object, {
    // replace the widget contents with an ajax call to render with params
    updateContent: function (params) {
        if (! params) params = {};
        this._show_frame = params["showFrame"];

        if ( params["method"] ) method = params["method"];
        params["_widget_update"] = 1;

        if (this.doAjaxRequest(params)) {
            // hilight the widget to show that its updating
            this.hilightFrame();
        }
    },

    // returns the widget element
    getWidget: function () {
        return $(this.widgetId);
    },

    // do a simple post to the widget
    doPost: function (params) {
        if (! params) params = {};
        this._show_frame = params["showFrame"];
        var postParams = {};

        var classPrefix = this.widgetClass;
        classPrefix = "Widget[" + classPrefix.replace(/::/g, "_") + "]_";

        for (var k in params) {
            var class_k = k;
            if (! k.match(/^Widget\[/) && k != 'lj_form_auth' && ! k.match(/^_widget/)) {
                class_k = classPrefix + k;
            }

            postParams[class_k] = params[k];
        }

        postParams["_widget_post"] = 1;

        this.doAjaxRequest(postParams);
    },

    doPostAndUpdateContent: function (params) {
        if (! params) params = {};

        params["_widget_update"] = 1;

        this.doPost(params);
    },

    // do an ajax post of the form passed in
    postForm: function (formElement) {
      if (! formElement) return false;

      var params = {};

      for (var i=0; i < formElement.elements.length; i++) {
        var element = formElement.elements[i];
        var name = element.name;
        var value = element.value;

        params[name] = value;
      }

      this.doPost(params);
    },

    ///////////////// PRIVATE METHODS ////////////////////

    init: function (id, widgetClass, authToken) {
        LJWidget.superClass.init.apply(this, arguments);
        this.widgetId = id;
        this.widgetClass = widgetClass;
        this.authToken = authToken;
    },

    hilightFrame: function () {
        if (this._show_frame != 1) return;
        if (this._frame) return;

        var widgetEle = this.getWidget();
        if (! widgetEle) return;

        var widgetParent = widgetEle.parentNode;
        if (! widgetParent) return;

        var enclosure = document.createElement("fieldset");
        enclosure.style.borderColor = "red";
        var title = document.createElement("legend");
        title.innerHTML = "Updating...";
        enclosure.appendChild(title);

        widgetParent.appendChild(enclosure);
        enclosure.appendChild(widgetEle);

        this._frame = enclosure;
    },

    removeHilightFrame: function () {
        if (this._show_frame != 1) return;

        var widgetEle = this.getWidget();
        if (! widgetEle) return;

        if (! this._frame) return;

        var par = this._frame.parentNode;
        if (! par) return;

        par.appendChild(widgetEle);
        par.removeChild(this._frame);

        this._frame = null;
    },

    method: "POST",
    endpoint: "widget",
    requestParams: {},

    doAjaxRequest: function (params) {
        if (! params) params = {};

        if (this._ajax_updating) return false;
        this._ajax_updating = true;

        params["_widget_id"]     = this.widgetId;
        params["_widget_class"]  = this.widgetClass;

        params["auth_token"]  = this.authToken;


        if ($('_widget_authas')) {
            params["authas"] = $('_widget_authas').value;
        }

        var reqOpts = {
            method:  this.method,
            data:    HTTPReq.formEncoded(params),
            url:     LiveJournal.getAjaxUrl(this.endpoint),
            onData:  this.ajaxDone.bind(this),
            onError: this.ajaxError.bind(this)
        };

        for (var k in params) {
            reqOpts[k] = params[k];
        }

        HTTPReq.getJSON(reqOpts);

        return true;
    },

    ajaxDone: function (data) {
        this._ajax_updating = false;
        this.removeHilightFrame();
 	
	if(data["_widget_body"]){	
		if(data["_widget_body"].match(/ajax:.[^"]+/)){
			this.authToken=data["_widget_body"].match(/ajax:.[^"]+/)[0];
		}
	}

        if (data.auth_token) {
            this.authToken = data.auth_token;
        }

        if (data.errors && data.errors != '') {
            return this.ajaxError(data.errors);
        }

        if (data.error) {
            return this.ajaxError(data.error);
        }

        // call callback if one exists
        if (this.onData) {
             this.onData(data);
        }

        if (data["_widget_body"]) {
            // did an update request, got the new body back
            var widgetEle = this.getWidget();
            if (! widgetEle) {
              // widget is gone, ignore
              return;
            }

            widgetEle.innerHTML = data["_widget_body"];

            if (this.onRefresh) {
                this.onRefresh();
            }
        }
	
    },

    ajaxError: function (err) {
        this._ajax_updating = false;

        if (this.onError) {
            // use class error handler
            this.onError(err);
        } else {
            // use generic error handler
            LiveJournal.ajaxError(err);
        }
    }
});

LJWidget.widgets = [];

LJWidgetIPPU = new Class(LJWidget, {
    init: function (opts, reqParams) {
        var title = opts.title;
        var widgetClass = opts.widgetClass;
        var authToken = opts.authToken;
        var nearEle = opts.nearElement;
        var not_view_close = opts.not_view_close;

        if (! reqParams) reqParams = {};
        this.reqParams = reqParams;

        // construct a container ippu for this widget
        var ippu = new LJ_IPPU(title, nearEle);
        this.ippu = ippu;
        var c = document.createElement("div");
        c.id = "LJWidgetIPPU_" + Unique.id();
        ippu.setContentElement(c);

        if (opts.width && opts.height)
          ippu.setDimensions(opts.width, opts.height);

        if (opts.overlay) {
            if (IPPU.isIE()) {
                this.ippu.setModal(true);
                this.ippu.setOverlayVisible(true);
                this.ippu.setClickToClose(false);
            } else {
                this.ippu.setModal(true);
                this.ippu.setOverlayVisible(true);
            }
        }

        if (opts.center) ippu.center();
        ippu.show();
        if (not_view_close) ippu.titlebar.getElementsByTagName('img')[0].style.display = 'none';

        var loadingText = document.createElement("div");
        loadingText.style.fontSize = '1.5em';
        loadingText.style.fontWeight = 'bold';
        loadingText.style.margin = '5px';
        loadingText.style.textAlign = 'center';

        loadingText.innerHTML = "Loading...";

        this.loadingText = loadingText;

        c.appendChild(loadingText);

        // id, widgetClass, authToken
        var widgetArgs = [c.id, widgetClass, authToken]
        LJWidgetIPPU.superClass.init.apply(this, widgetArgs);

        if (!widgetClass)
            return null;

        this.widgetClass = widgetClass;
        this.authToken = authToken;
        this.title = title;
        this.nearEle = nearEle;

        window.setInterval(this.animateLoading.bind(this), 20);

        this.loaded = false;

        // start request for this widget now
        this.loadContent();
        return this;
    },

    animateCount: 0,

    animateLoading: function (i) {
      var ele = this.loadingText;

      if (this.loaded || ! ele) {
        window.clearInterval(i);
        return;
      }

      this.animateCount += 0.05;
      var intensity = ((Math.sin(this.animateCount) + 1) / 2) * 255;
      var hexColor = Math.round(intensity).toString(16);

      if (hexColor.length == 1) hexColor = "0" + hexColor;
      hexColor += hexColor + hexColor;

      ele.style.color = "#" + hexColor;
      this.ippu.center();
    },

    // override doAjaxRequest to add _widget_ippu = 1
    doAjaxRequest: function (params) {
      if (! params) params = {};
      params['_widget_ippu'] = 1;
      if(document.getElementById("LJ__Setting__InvisibilityGuests_invisibleguests_self")){
      	params['Widget[IPPU_SettingProd]_LJ__Setting__InvisibilityGuests_invisibleguests']=
	      (document.getElementById("LJ__Setting__InvisibilityGuests_invisibleguests_self").checked==true)?(1):((document.getElementById("LJ__Setting__InvisibilityGuests_invisibleguests_anon").checked==true)?(2):(0))
      }
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
      this.loaded = true;
    },

    render: function (params) {

    }
});

LJWidgetIPPU_AddAlias = new Class(LJWidgetIPPU, {
  init: function (opts, params) {
    opts.widgetClass = "IPPU::AddAlias";
    this.width = opts.width; // Use for resizing later
    this.height = opts.height; // Use for resizing later
    this.alias = opts.alias;  
    LJWidgetIPPU_AddAlias.superClass.init.apply(this, arguments);
  },

  addvgifttocart: function (evt, form) {
    var alias = form["Widget[IPPU_AddAlias]_alias"].value + "";
    var foruser = form["Widget[IPPU_AddAlias]_foruser"].value + "";

    this.doPost({
        alias:          alias,
        foruser:            foruser
    });

    Event.stop(evt);
  },

  onData: function (data) {
	if (!data.res || !data.res.success) {
		return;
	}
	this.ippu.hide();
	var userLJ = data.res.journalname,
		userClassName = 'ljuser-name_' + data.res.journalname,
		searchProfile = DOM.getElementsByClassName(document, userClassName),
		i = -1, supSign;
	while (searchProfile[++i]) {
		var ljuser_node = searchProfile[i];
		if (DOM.hasClassName(ljuser_node, 'with-alias-value')) {
			var alias_value = ljuser_node.nextSibling;
			if (!alias_value || alias_value.tagName != 'SPAN' || alias_value.className != 'alias-value') {
				alias_value = null;
			}
			if (data.res.alias) {
				if (!alias_value) {
					alias_value = document.createElement('span');
					alias_value.className = 'alias-value';
					alias_value[/*@cc_on'innerText'||@*/'textContent'] = ' — ' + data.res.alias;
					ljuser_node.parentNode[ljuser_node.nextSibling ? 'insertBefore' : 'appendChild'](alias_value);
				}
				alias_value[/*@cc_on'innerText'||@*/'textContent'] = ' — ' + data.res.alias;
			} else if (alias_value) { // delete
				ljuser_node.parentNode.removeChild(alias_value);
			}
		} else if (!DOM.hasClassName(ljuser_node, 'with-alias')) {
			DOM.addClassName(searchProfile[i],'with-alias')
			supSign=document.createElement('span');
			DOM.addClassName(supSign,'useralias-value');
			supSign.innerHTML='*';
			searchProfile[i].getElementsByTagName('a')[1].appendChild(supSign);
		}else{
			if(!data.res.alias){
				DOM.removeClassName(searchProfile[i],'with-alias')
				supSign=DOM.getElementsByClassName(searchProfile[i],'useralias-value')[0];
				searchProfile[i].getElementsByTagName('a')[1].removeChild(supSign);
			}
		}
		searchProfile[i].getElementsByTagName('a')[1].setAttribute('title',data.res.alias);
	}
	//Changing button. Only on profile page
	var edit_node = DOM.getElementsByClassName(document, 'profile_addalias');
	if (edit_node.length) {
		if (data.res.alias) {
			edit_node[0].style.display = 'none';
			edit_node[1].style.display = 'block';
			edit_node[1].firstChild.alias = data.res.alias;
		} else {
			edit_node[0].style.display = 'block';
			edit_node[1].style.display = 'none';
		}
	}
	
	if(ContextualPopup.cachedResults[data.res.username]) {
		ContextualPopup.cachedResults[data.res.username].alias_title = data.res.alias ? 'Edit Note' : 'Add Note';
		ContextualPopup.cachedResults[data.res.username].alias = data.res.alias;
	}
  },

  onError: function (msg) {
    LJ_IPPU.showErrorNote("Error: " + msg);
  },

  onRefresh: function () {
	var form = $("addalias_form"),
		input = form['Widget[IPPU_AddAlias]_alias'],
		delete_btn = form['Widget[IPPU_AddAlias]_aliasdelete'],
		t = this;
	input.focus();
	
	if (delete_btn) {
		delete_btn.onclick=function(){
			input.value = '';
		}
		input.onkeyup =
		input.onpaste =
		input.oninput = function() {
			// save button disabled
			form['Widget[IPPU_AddAlias]_aliaschange'].disabled = !this.value;
		}
	}
	
	DOM.addEventListener(form, 'submit', function(e) { t.addvgifttocart(e, form) });
//    $('Widget[IPPU_AddAlias]_whom').value = this.whom;
//    AutoCompleteFriends($('Widget[IPPU_AddAlias]_whom'));
  },

  cancel: function (e) {
    this.close();
  }
});


Aliases = {}
function addAlias(target, ptitle, ljusername, oldalias, callback) {
    if (! ptitle) return true;
	
	new LJWidgetIPPU_AddAlias({
        title: ptitle,
        width: 440,
        height: 180,
		authToken: Aliases.authToken,
		callback: callback
        }, {
	    alias: target.alias||oldalias,
            foruser: ljusername
        });

    return false;
}


var ContextualPopup =
{
	popupDelay  : 500,
	hideDelay   : 250,
	
	cachedResults  : {},
	currentRequests: {},
	mouseInTimer   : null,
	mouseOutTimer  : null,
	currentId      : null,
	hourglass      : null,
	
	setup: function()
	{
		// don't do anything if no remote
		if (!Site.ctx_popup) return;
		
		jQuery(document.body)
			.mouseover(ContextualPopup.mouseOver)
			.ljAddContextualPopup();
	},
	
	searchAndAdd: function(node)
	{
		if (!Site.ctx_popup) return;
		
		// attach to all ljuser head icons
		var rex_userid = /\?userid=(\d+)/,
			rex_userpic = /(userpic\..+\/\d+\/\d+)|(\/userpic\/\d+\/\d+)/,
			ljusers = jQuery('span.ljuser>a>img', node),
			i = -1, userid, ljuser, parent;
		
		// use while for speed
		while (ljusers[++i])
		{
			var ljuser = ljusers[i], parent = ljuser.parentNode;
			if (parent.href && (userid = parent.href.match(rex_userid))) {
				ljuser.userid = userid[1];
			} else if (parent.parentNode.getAttribute('lj:user')) {
				ljuser.username = parent.parentNode.getAttribute('lj:user');
			} else {
				continue;
			}
			jQuery.className.add(ljuser, 'ContextualPopup');
		}
		
		ljusers = node.getElementsByTagName('img');
		i = -1;
		while (ljusers[++i])
		{
			ljuser = ljusers[i];
			if (ljuser.src.match(rex_userpic)) {
				ljuser.up_url = ljuser.src;
				jQuery.className.add(ljuser, 'ContextualPopup');
			}
		}
	},
	
	mouseOver: function(e)
	{
		var target = e.target,
			ctxPopupId = target.username || target.userid || target.up_url,
			t = ContextualPopup;
		
		clearTimeout(t.mouseInTimer);
		
		if (ctxPopupId) {
			// if we don't have cached data background request it
			if (!t.cachedResults[ctxPopupId]) {
				t.getInfo(target, ctxPopupId);
			}
			
			// doesn't display alt as tooltip
			if (jQuery.browser.msie && target.title !== undefined) {
				target.title = '';
			}
			
			if (t.ippu) {
				clearTimeout(t.mouseOutTimer);
				t.mouseOutTimer = null;
				// show other popup
				if (t.current_target != target) {
					t.showPopup(ctxPopupId, target);
				}
			}
			// start timer if it's not running
			else {
				t.mouseInTimer = setTimeout(function()
				{
					t.showPopup(ctxPopupId, target);
				}, t.popupDelay);
			}
		} else if (t.ippu) {
			// we're inside a ctxPopElement, cancel the mouseout timer
			if (jQuery(target).closest('.ContextualPopup').length) {
				clearTimeout(t.mouseOutTimer);
				t.mouseOutTimer = null;
			}
			// did the mouse move out?
			else if (t.mouseOutTimer === null) {
				t.mouseOutTimer = setTimeout(function()
				{
					t.mouseOut();
				}, t.hideDelay);
			}
		}
	},
	
	mouseOut: function()
	{
		clearTimeout(ContextualPopup.mouseOutTimer);
		
		ContextualPopup.mouseOutTimer =
		ContextualPopup.currentId =
		ContextualPopup.current_target = null;
		
		ContextualPopup.hidePopup();
	},
	
	showPopup: function(ctxPopupId, ele)
	{
		ContextualPopup.current_target = ele;
		ContextualPopup.currentId = ctxPopupId;
		var data = ContextualPopup.cachedResults[ctxPopupId];
		
		if (data && data.noshow) return;
		
		ContextualPopup.constructIPPU(ctxPopupId);
		var ippu = ContextualPopup.ippu;
		// default is to auto-center, don't want that
		ippu.setAutoCenter(false, false);
	
		// pop up the box right under the element
		ele = jQuery(ele);
		var ele_offset = ele.offset(),
			left = ele_offset.left,
			top = ele_offset.top + ele.height();
		
		// hide the ippu content element, put it on the page,
		// get its bounds and make sure it's not going beyond the client
		// viewport. if the element is beyond the right bounds scoot it to the left.
		var pop_ele = ippu.getElement();
		pop_ele.style.visibility = 'hidden';
		
		// put the content element on the page so its dimensions can be found
		ippu.show();
		
		var win_width = jQuery(document).width(),
			win_height = jQuery(document).height(),
			pop_width = jQuery(pop_ele).outerWidth(true),
			pop_height = jQuery(pop_ele).outerHeight(true);
		
		if (left + pop_width > win_width) {
			left = win_width - pop_width;
		}
		
		if (top + pop_height > win_height) {
			top = win_height - pop_height;
		}
		
		ippu.setLocation(left, top);
		
		// finally make the content visible
		pop_ele.style.visibility = 'visible';
	}
}

// if the popup was not closed by us catch it and handle it
ContextualPopup.popupClosed = function () {
    ContextualPopup.mouseOut();
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
        bar.innerHTML = "&nbsp;| ";

        // userpic
        if (data.url_userpic && data.url_userpic != ctxPopupId) {
            var userpicContainer = document.createElement("div");
            var userpicLink = document.createElement("a");
            userpicLink.href = data.url_allpics;
            var userpic = document.createElement("img");
            userpic.src = data.url_userpic;
            userpic.width = data.userpic_w;
            userpic.height = data.userpic_h;

            userpicContainer.appendChild(userpicLink);
            userpicLink.appendChild(userpic);
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
	
	// aliases
	
	var alias;
	if(!data.is_requester && data.is_logged_in!='0'){
            	alias = document.createElement('span');
		if(data.alias_enable!=0){
			if(data.alias){
				var currentalias=document.createElement('span');
				currentalias[/*@cc_on'innerText'||@*/'textContent']=data.alias;
				DOM.addClassName(currentalias,'alias-value');
				content.insertBefore(currentalias,content.firstChild.nextSibling);
				var editalias=document.createElement('a');
				editalias.href='javascript:void(0)';
				editalias.onclick=function(){return addAlias(this, data.alias_title, data.username, data.alias);}
				editalias.innerHTML=data.alias_title;
				alias.appendChild(editalias);
				DOM.addClassName(alias,'alias-edit');
			}
			else{
				var addalias=document.createElement('a');
				addalias.href='javascript:void(0)';
				addalias.onclick=function(){return addAlias(this, data.alias_title, data.username,'');}
				addalias.innerHTML=data.alias_title;
				alias.appendChild(addalias);
				DOM.addClassName(alias,'alias-add');
			}
		}else{
			var disabledalias=document.createElement('a');
			var upgradeacc=document.createElement('a');
			var upgradeimg=document.createElement('img');
            		upgradeacc.href=window.Site.siteroot+'/manage/account';
			var statroot=window.Site.siteroot.toString();
			var statsiteroot=statroot.replace(/http\:\/\/www\./,'http://stat.');
			upgradeimg.src=statsiteroot+'/horizon/upgrade-paid-icon.gif';
			upgradeimg.alt='';
			upgradeacc.appendChild(upgradeimg);
			disabledalias.href=window.Site.siteroot+'/support/faqbrowse.bml?faqid=295';
			disabledalias.innerHTML='Add Note';
			alias.appendChild(upgradeacc);
			alias.innerHTML+="&nbsp";
			alias.appendChild(disabledalias);
			DOM.addClassName(alias,'alias-unavailable');


		}	
	content.appendChild(alias);
    	content.appendChild(document.createElement("br"));
	}

        // member of community
        if (data.is_logged_in && data.is_comm) {
            var membership     = document.createElement("span");
            var membershipLink = document.createElement("a");

            var membership_action = data.is_member ? "leave" : "join";

            if (data.is_member) {
                membershipLink.href = data.url_leavecomm;
                membershipLink.innerHTML = "Leave";
            } else {
                membershipLink.href = data.url_joincomm;
                membershipLink.innerHTML = "Join community";
            }

            DOM.addEventListener(membershipLink, "click", function (e) {
                Event.prep(e);
                Event.stop(e);
                return ContextualPopup.changeRelation(data, ctxPopupId, membership_action, e);
            });

            membership.appendChild(membershipLink);
            content.appendChild(membership);
        }

	
// send message
var message;
if (data.is_logged_in && data.is_person && ! data.is_requester && data.url_message) {
    message = document.createElement("span");

    var sendmessage = document.createElement("a");
    sendmessage.href = data.url_message;
    sendmessage.innerHTML = "Send message";

    message.appendChild(sendmessage);
    content.appendChild(message);
}

// friend
var friend;
if (data.is_logged_in && ! data.is_requester) {
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

	DOM.addEventListener(addFriendLink, "click", function (e) {
		Event.prep(e);
		Event.stop(e);
		return ContextualPopup.changeRelation(data, ctxPopupId, "addFriend", e);
	});

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

	DOM.addEventListener(removeFriendLink, "click", function (e) {
		Event.stop(e);
		return ContextualPopup.changeRelation(data, ctxPopupId, "removeFriend", e);
	});

	friend.appendChild(removeFriend);
    }

    DOM.addClassName(relation, "FriendStatus");
}

// add a bar between stuff if we have community actions
if ((data.is_logged_in && data.is_comm) || (message && friend))
    content.appendChild(document.createElement("br"));

        if (friend)
            content.appendChild(friend);

        if ((data.is_person || data.is_comm) && !data.is_requester && data.can_receive_vgifts) {
            var vgift = document.createElement("span");

            var sendvgift = document.createElement("a");
            sendvgift.href = window.Site.siteroot + "/shop/vgift.bml?to=" + data.username;
            sendvgift.innerHTML = "Send a virtual gift";

            vgift.appendChild(sendvgift);

            if (friend)
                content.appendChild(document.createElement("br"));

            content.appendChild(vgift);
        }

        // ban / unban
        var ban;
		if (data.is_logged_in && !data.is_requester && !data.is_comm && !data.is_syndicated) {
            ban = document.createElement("span");

            if(!data.is_banned) {
                // if user no banned - show ban link
                var setBan = document.createElement("span");
                var setBanLink = document.createElement("a");
                
                setBanLink.href = window.Site.siteroot + '/manage/banusers.bml';
                setBanLink.innerHTML = 'Ban user';
                
                setBan.appendChild(setBanLink);

                DOM.addClassName(setBan, "SetBan");

                DOM.addEventListener(setBanLink, "click", function (e) {
                    Event.prep(e);
                    Event.stop(e);
                    return ContextualPopup.changeRelation(data, ctxPopupId, "setBan", e);
                });

                ban.appendChild(setBan);
            } else {
                // if use banned - show unban link
                var setUnban = document.createElement("span");
                var setUnbanLink = document.createElement("a");
                setUnbanLink.href = window.Site.siteroot + '/manage/banusers.bml';
                setUnbanLink.innerHTML = 'Unban user';
                setUnban.appendChild(setUnbanLink);

                DOM.addClassName(setUnban, "SetUnban");

                DOM.addEventListener(setUnbanLink, "click", function (e) {
                    Event.prep(e);
                    Event.stop(e);
                    return ContextualPopup.changeRelation(data, ctxPopupId, "setUnban", e);
                });

                ban.appendChild(setUnban);
            }
        }

        if(ban) {
            content.appendChild(document.createElement("br"));
            content.appendChild(ban);
        }

        var report_bot;
		if (data.is_logged_in && !data.is_requester  && !data.is_comm && !data.is_syndicated && !window.Site.remote_is_suspended) {
            var report_bot = document.createElement('a');
            report_bot.href = window.Site.siteroot + '/abuse/bots.bml?user=' + data.username;
            report_bot.innerHTML = 'Report a Bot';
        }

        if(report_bot) {
            content.appendChild(bar.cloneNode(true));
            content.appendChild(report_bot);
        }

		// ban user from all maintained communities
		if (!data.is_requester && !data.is_comm && !data.is_syndicated && data.have_communities) {
			var ban_everywhere = document.createElement('a');
			ban_everywhere.href = Site.siteroot + '/manage/banusers.bml';
			ban_everywhere.innerHTML = data.is_banned_everywhere ? data.unban_everywhere_title : data.ban_everywhere_title;
			DOM.addEventListener(ban_everywhere, 'click', function(e) {
				Event.prep(e);
				Event.stop(e);
				var action = data.is_banned_everywhere ? 'unbanEverywhere' : 'banEverywhere';
				return ContextualPopup.changeRelation(data, ctxPopupId, action, e);
			});
			content.appendChild(document.createElement('br'));
			content.appendChild(ban_everywhere);
		}

        // break
        if ((data.is_logged_in && !data.is_requester) || vgift) content.appendChild(document.createElement("br"));

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
ContextualPopup.changeRelation = function (info, ctxPopupId, action, e) {
	var changedRelation = function(data)
	{
		if (data.error) {
			return ContextualPopup.showNote(data.error);
		}
		
		if (ContextualPopup.cachedResults[ctxPopupId]) {
			jQuery.extend(ContextualPopup.cachedResults[ctxPopupId], data);
		}
		
		// if the popup is up, reload it
		ContextualPopup.renderPopup(ctxPopupId);
	}
	
	var xhr = jQuery.post(LiveJournal.getAjaxUrl('changerelation'),
				{
					target: info.username,
					action: action,
					auth_token: info[action + '_authtoken']
				},
				function(data)
				{
					ContextualPopup.hourglass = null;
					changedRelation(data);
				},
				'json'
			);
	
	ContextualPopup.hideHourglass();
	ContextualPopup.hourglass = jQuery(e).hourglass(xhr)[0];
	// so mousing over hourglass doesn't make ctxpopup think mouse is outside
	ContextualPopup.hourglass.add_class_name('lj_hourglass ContextualPopup');
	
	return false;
}

// create a little popup to notify the user of something
ContextualPopup.showNote = function (note, ele) {
    if (ContextualPopup.ippu) {
        // pop up the box right under the element
        ele = ContextualPopup.ippu.getElement();
    }

    LJ_IPPU.showNote(note, ele);
}

ContextualPopup.hidePopup = function (ctxPopupId) {
	ContextualPopup.hideHourglass();
	
    // destroy popup for now
    if (ContextualPopup.ippu) {
        ContextualPopup.ippu.hide();
        ContextualPopup.ippu = null;
    }
}

// do ajax request of user info
ContextualPopup.getInfo = function(target, ctxPopupId)
{
	if (ContextualPopup.currentRequests[ctxPopupId]) return;
	
	ContextualPopup.currentRequests[ctxPopupId] = 1;
	
	// got data callback
	var gotInfo = function (data)
	{
		ContextualPopup.cachedResults[String(data.userid)] =
		ContextualPopup.cachedResults[data.username] =
		ContextualPopup.cachedResults[data.url_userpic] = data;
		
		// non default userpic
		if (target.up_url) {
			ContextualPopup.cachedResults[target.up_url] = data;
		}
		
		if (data.error) {
			!data.noshow && ContextualPopup.showNote(data.error, target);
			return;
		}
		
		ContextualPopup.currentRequests[ctxPopupId] = null;
		
		if (ContextualPopup.currentId == ctxPopupId) {
			ContextualPopup.renderPopup(ctxPopupId);
		}
	};
	
	jQuery.getJSON(
		LiveJournal.getAjaxUrl('ctxpopup'),
		{
			user: target.username || '',
			userid: target.userid || 0,
			userpic_url: target.up_url || '',
			mode: 'getinfo'
		},
		gotInfo
	);
}

ContextualPopup.hideHourglass = function () {
    if (ContextualPopup.hourglass) {
        ContextualPopup.hourglass.hide();
        ContextualPopup.hourglass = null;
    }
}

// when page loads, set up contextual popups
jQuery(ContextualPopup.setup);
