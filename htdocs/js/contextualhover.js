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
					ljuser_node.parentNode.insertBefore(alias_value, ljuser_node.nextSibling);
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
			DOM.addClassName(ljuser, 'ContextualPopup');
		}
		
		ljusers = node.getElementsByTagName('img');
		i = -1;
		while (ljusers[++i])
		{
			ljuser = ljusers[i];
			if (ljuser.src.match(rex_userpic)) {
				ljuser.up_url = ljuser.src;
				DOM.addClassName(ljuser, 'ContextualPopup');
			}
		}
	},
	
	mouseOver: function(e)
	{
		var target = e.target,
			ctxPopupId = target.username || target.userid || target.up_url,
			t = ContextualPopup;
		
		clearTimeout(t.mouseInTimer);
		
		if (target.tagName == 'IMG' && ctxPopupId) {
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
	
	constructIPPU: function (ctxPopupId)
	{
		if (ContextualPopup.ippu) {
			ContextualPopup.ippu.hide();
			ContextualPopup.ippu = null;
		}
		ContextualPopup.ippu =
		{
			element: jQuery('<div class="ContextualPopup"></div>'),
			show: function()
			{
				document.body.appendChild(this.element[0]);
			},
			hide: function()
			{
				this.element.remove();
			}
		}
		
		ContextualPopup.renderPopup(ctxPopupId);
	},
	
	showPopup: function(ctxPopupId, ele)
	{
		ContextualPopup.current_target = ele;
		ContextualPopup.currentId = ctxPopupId;
		var data = ContextualPopup.cachedResults[ctxPopupId];
		
		if (data && data.noshow) return;
		
		ContextualPopup.constructIPPU(ctxPopupId);
		var ippu = ContextualPopup.ippu;
		
		// pop up the box right under the element
		ele = jQuery(ele);
		var ele_offset = ele.offset(),
			left = ele_offset.left,
			top = ele_offset.top + ele.height();
		
		// hide the ippu content element, put it on the page,
		// get its bounds and make sure it's not going beyond the client
		// viewport. if the element is beyond the right bounds scoot it to the left.
		var pop_ele = ippu.element;
		pop_ele.css('visibility', 'hidden');
		
		// put the content element on the page so its dimensions can be found
		ippu.show();
		
		ContextualPopup.calcPosition(pop_ele, left, top);
		
		// finally make the content visible
		pop_ele.css('visibility', 'visible');
	},
	
	//calc with viewport
	calcPosition: function(pop_ele, left, top)
	{
		var $window = jQuery(window);
		
		left = Math.min(left,  $window.width() + $window.scrollLeft() - pop_ele.outerWidth(true));
		top = Math.min(top, $window.height() + $window.scrollTop() - pop_ele.outerHeight(true));
		
		pop_ele.css({
			left: left,
			top: top
		});
	}
}

// if the popup was not closed by us catch it and handle it
ContextualPopup.popupClosed = function () {
    ContextualPopup.mouseOut();
}

ContextualPopup.renderPopup = function(ctxPopupId)
{
	var ippu = ContextualPopup.ippu;
	
	if (!ippu || !ctxPopupId) {
		return;
	}
	
	var data = ContextualPopup.cachedResults[ctxPopupId];
	
	if (!data) {
		ippu.element.append('<div class="Inner">Loading...</div>');
		return;
	} else if (!data.username || !data.success || data.noshow) {
		ContextualPopup.hidePopup();
		return;
	}
	
	var inner = jQuery('<div class="Inner"/>');
	// if "Loading..." text
	var last_inner_height;
	if (ippu.element[0].firstChild) {
		last_inner_height = ippu.element[0].firstChild.offsetHeight;
		ippu.element.height(ippu.element.height());
		ippu.element.css('overflow', 'hidden');
	}
	
	var bar = document.createElement('span');
	bar.innerHTML = '&nbsp;| ';
	
	// userpic
	if (data.url_userpic && data.url_userpic != ctxPopupId) {
		jQuery(
			'<div class="Userpic">'+
				'<a href="'+data.url_allpics+'">'+
					'<img src="'+data.url_userpic+'" width="'+data.userpic_w+'" height="'+data.userpic_h+'"/>'+
				'</a>'+
			'</div>'
		)
		.appendTo(inner);
	}
	
	var content = document.createElement('div');
	content.className = 'Content';
	
	inner.append(content);
	
	// relation
	var label, username = data.display_username;
	if (data.is_comm) {
		if (data.is_member)
			label = data.ml_you_member.replace('[[username]]', username);
		else if (data.is_friend)
			labelL = data.ml_you_watching.replace('[[username]]', username);
		else
			label = username;
	} else if (data.is_syndicated) {
		if (data.is_friend)
				label = data.ml_you_subscribed.replace('[[username]]', username);
		else
			label = username;
	} else {
		if (data.is_requester) {
			label = data.ml_this_is_you;
		} else {
			label = username + ' ';
			
			if (data.is_friend_of) {
				if (data.is_friend)
					label += data.ml_mutual_friend;
				else
					label += data.ml_lists_as_friend;
			} else if (data.is_friend) {
				label += data.ml_your_friend;
			}
		}
	}
	jQuery('<div/>', {
		'class': 'Relation',
		text: label
	})
	.appendTo(content);
	
	// add site-specific content here
	var extraContent = LiveJournal.run_hook('ctxpopup_extrainfo', data);
	extraContent && content.appendChild(extraContent);
	
	// aliases
	if (!data.is_requester && data.is_logged_in) {
		if (data.alias_enable) {
			if (data.alias) {
				content.insertBefore(
					document.createTextNode(data.alias),
					content.firstChild.nextSibling
				);
			}
			
			jQuery('<a/>', {
				href: Site.siteroot + '/manage/notes.bml',
				text: data.alias_title,
				click: function(e)
				{
					e.preventDefault();
					addAlias(this, data.alias_title, data.username, data.alias || '');
				}
			})
			.appendTo(content);
		} else {
			jQuery(
				'<span class="alias-unavailable">'+
					'<a href="'+Site.siteroot+'/manage/account">'+
						'<img src="'+Site.statprefix+'/horizon/upgrade-paid-icon.gif" width="13" height="16" alt=""/>'+
					'</a> '+
					'<a href="'+Site.siteroot+'/support/faqbrowse.bml?faqid=295">'+data.alias_title+'</a>'+
				'</span>'
			)
			.appendTo(content)
		}
		
		content.appendChild(document.createElement('br'));
	}
	
	// member of community
	if (data.is_logged_in && data.is_comm) {
		jQuery('<a/>', {
			href: data.is_member ? data.ml_leave : data.url_joincomm,
			text: data.is_member ? data.ml_leave : data.ml_join_community,
			click: function(e)
			{
				e.preventDefault();
				ContextualPopup.changeRelation(data, ctxPopupId, data.is_member ? 'leave' : 'join', e);
			}
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	// buy the same userhead
	if (data.is_logged_in && data.is_person && ! data.is_requester && data.is_custom_userhead) {
		jQuery('<a/>', {
			href: data.url_buy_userhead,
			text: data.ml_buy_same_userhead
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	// send message
	if (data.is_logged_in && data.is_person && ! data.is_requester && data.url_message) {
		jQuery('<a/>', {
			href: data.url_message,
			text: data.ml_send_message
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	// add/remove friend link
	if (data.is_logged_in && !data.is_requester) {
		jQuery('<a/>', {
			href: data.url_addfriend,
			click: function(e)
			{
				e.preventDefault();
				ContextualPopup.changeRelation(data, ctxPopupId, data.is_friend ? 'removeFriend' : 'addFriend', e);
			},
			text: function()
			{
				if (data.is_comm)
					return data.is_friend ? data.ml_stop_community : data.ml_watch_community;
				else if (data.is_syndicated)
					return data.is_friend ? data.ml_unsubscribe_feed : data.ml_subscribe_feed;
				else
					return data.is_friend ? data.ml_remove_friend : data.ml_add_friend;
			}
		})
		.appendTo(content);
		if( data.is_friend ) {
			content.appendChild(bar.cloneNode(true));
			jQuery('<a/>', {
				href: data.url_addfriend,
				text: data.ml_edit_friend_tags
			})
			.appendTo(content);
		}
		content.appendChild(document.createElement('br'));
	}
	
	// vgift
	if ((data.is_person || data.is_comm) && !data.is_requester && data.can_receive_vgifts) {
		jQuery('<a/>', {
			href: Site.siteroot + '/shop/vgift.bml?to=' + data.username,
			text: data.ml_send_gift
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	// wishlist
	if ((data.is_person || data.is_comm) && !data.is_requester && data.wishlist_url) {
		jQuery('<a/>', {
			href:data.wishlist_url,
			text: data.ml_view_wishlist
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	if (data.is_logged_in && !data.is_requester && !data.is_comm && !data.is_syndicated) {
		// ban/unban
		jQuery('<a/>', {
			href: Site.siteroot + '/manage/banusers.bml',
			text: data.is_banned ? data.ml_unban : data.ml_ban,
			click: function(e)
			{
				e.preventDefault();
				ContextualPopup.changeRelation(data, ctxPopupId, data.is_banned ? 'setUnban' : 'setBan', e);
			}
		})
		.appendTo(content);
		
		// report a bot
		if (!Site.remote_is_suspended) {
			content.appendChild(bar.cloneNode(true));
			
			jQuery('<a/>', {
				href: Site.siteroot + '/abuse/bots.bml?user=' + data.username,
				text: data.ml_report
			})
			.appendTo(content);
		}
		
		content.appendChild(document.createElement('br'));
	}
	
	// ban user from all maintained communities
	if (!data.is_requester && !data.is_comm && !data.is_syndicated && data.have_communities) {
		jQuery('<a/>', {
			href: Site.siteroot + '/manage/banusers.bml',
			text: data.is_banned_everywhere ? data.unban_everywhere_title : data.ban_everywhere_title,
			click: function(e)
			{
				e.preventDefault();
				var action = data.is_banned_everywhere ? 'unbanEverywhere' : 'banEverywhere';
				ContextualPopup.changeRelation(data, ctxPopupId, action, e);
			}
		})
		.appendTo(content);
		content.appendChild(document.createElement('br'));
	}
	
	// identity
	if (data.is_identity) {
		jQuery('<a/>', {
			href: Site.siteroot + '/identity/convert.bml',
			text: data.ml_upgrade_account
		})
		.appendTo(content);
		
		content.appendChild(document.createElement('br'));
	}
	
	// view label
	content.appendChild(document.createTextNode(data.ml_view));
	
	// journal
	if (data.is_person || data.is_comm || data.is_syndicated) {
		jQuery('<a/>', {
			href: data.url_journal,
			text: function()
			{
				if (data.is_person)
					return data.ml_journal;
				else if (data.is_comm)
					return data.ml_community;
				else if (data.is_syndicated)
					return data.ml_feed;
			}
		})
		.appendTo(content)
		
		content.appendChild(bar.cloneNode(true));
	}
	
	// profile
	jQuery('<a/>', {
		href: data.url_profile,
		text: data.ml_profile
	})
	.appendTo(content);
	
	// clearing div
	jQuery('<div class="ljclear">&nbsp;</div>')
	.appendTo(content);
	
	ippu.element.html(inner);
	
	//calc position with viewport
	if (last_inner_height) {
		var $window = jQuery(window),
			top = parseInt(ippu.element[0].style.top),
			diff = ippu.element[0].firstChild.offsetHeight - last_inner_height,
			new_top = Math.min(top, $window.height() + $window.scrollTop() - ippu.element.outerHeight(true) - diff);
		top != new_top && ippu.element.css('top', new_top);
		ippu.element.css('overflow', 'visible');
	}
	
	if (!data.is_logged_in) { //  anonymouse
		new Image().src = 'http://ad.adriver.ru/cgi-bin/rle.cgi?sid=1&ad=186396&bt=21&pid=482107&bid=893162&bn=893162&rnd='+Math.random();
	} else if (data.is_requester) { // self
		new Image().src = 'http://ad.adriver.ru/cgi-bin/rle.cgi?sid=1&ad=186396&bt=21&pid=482107&bid=893165&bn=893165&rnd='+Math.random();
	} else { // not self
		new Image().src = 'http://ad.adriver.ru/cgi-bin/rle.cgi?sid=1&ad=186396&bt=21&pid=482107&bid=893167&bn=893167&rnd='+Math.random();
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
        ele = ContextualPopup.ippu.element[0];
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
ContextualPopup.getInfo = function(target, popup_id)
{
	var t = this;
	if (t.currentRequests[popup_id]) {
		return;
	}
	t.currentRequests[popup_id] = 1;
	
	jQuery.ajax({
		url: LiveJournal.getAjaxUrl('ctxpopup'),
		data: {
			user: target.username || '',
			userid: target.userid || 0,
			userpic_url: target.up_url || '',
			mode: 'getinfo'
		},
		dataType: 'json',
		success: function(data)
		{
			if (data.error) {
				ContextualPopup.hidePopup();
				t.showNote(data.error, target);
				return;
			}
			
			t.cachedResults[String(data.userid)] =
			t.cachedResults[data.username] =
			t.cachedResults[data.url_userpic] = data;
			
			// non default userpic
			if (target.up_url) {
				t.cachedResults[target.up_url] = data;
			}
			
			t.currentRequests[popup_id] = null;
			
			if (t.currentId == popup_id) {
				t.renderPopup(popup_id);
			}
		},
		error: function()
		{
			t.currentRequests[popup_id] = null;
		}
	});
}

ContextualPopup.hideHourglass = function () {
    if (ContextualPopup.hourglass) {
        ContextualPopup.hourglass.hide();
        ContextualPopup.hourglass = null;
    }
}

// when page loads, set up contextual popups
jQuery(ContextualPopup.setup);
