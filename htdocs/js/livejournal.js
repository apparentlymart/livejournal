// This file contains general-purpose LJ code
LiveJournal = {
	hooks: {} // The hook mappings
}

LiveJournal.register_hook = function (hook, func) {
    if (! LiveJournal.hooks[hook])
        LiveJournal.hooks[hook] = [];

    LiveJournal.hooks[hook].push(func);
};

// args: hook, params to pass to hook
LiveJournal.run_hook = function () {
    var a = arguments;

    var hookfuncs = LiveJournal.hooks[a[0]];
    if (!hookfuncs || !hookfuncs.length) return;

    var hookargs = [];

    for (var i = 1; i < a.length; i++) {
        hookargs.push(a[i]);
    }

    var rv = null;

    hookfuncs.forEach(function (hookfunc) {
        rv = hookfunc.apply(null, hookargs);
    });

    return rv;
};

LiveJournal.initPage = function () {
    // set up various handlers for every page
    LiveJournal.initInboxUpdate();

    // run other hooks
    LiveJournal.run_hook("page_load");
};

jQuery(LiveJournal.initPage);

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
    // Don't run if not logged in or this is disabled
    if (! Site || ! Site.has_remote || ! Site.inbox_update_poll) return;

    // Don't run if no inbox count
    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

    // Update every five minutes
    window.setInterval(LiveJournal.updateInbox, 1000 * 60 * 5);
};

// Do AJAX request to find the number of unread items in the inbox
LiveJournal.updateInbox = function () {
    var postData = {
        "action": "get_unread_items"
    };

    var opts = {
        "data": HTTPReq.formEncoded(postData),
        "method": "POST",
        "onData": LiveJournal.gotInboxUpdate
    };

    opts.url = Site.currentJournal ? "/" + Site.currentJournal + "/__rpc_esn_inbox" : "/__rpc_esn_inbox";

    HTTPReq.getJSON(opts);
};

// We received the number of unread inbox items from the server
LiveJournal.gotInboxUpdate = function (resp) {
    if (! resp || resp.error) return;

    var unread = $("LJ_Inbox_Unread_Count");
    if (! unread) return;

    unread.innerHTML = resp.unread_count ? "  (" + resp.unread_count + ")" : "";
};

// Placeholder onclick event
LiveJournal.placeholderClick = function(link, html)
{
	// use replaceChild for no blink scroll effect
	link.parentNode.parentNode.replaceChild(jQuery(unescape(html))[0], link.parentNode);
	
	return false
}

// handy utilities to create elements with just text in them
function _textSpan () { return _textElements("span", arguments); }
function _textDiv  () { return _textElements("div", arguments);  }

function _textElements (eleType, txts) {
    var ele = [];
    for (var i = 0; i < txts.length; i++) {
        var node = document.createElement(eleType);
        node.innerHTML = txts[i];
        ele.push(node);
    }

    return ele.length == 1 ? ele[0] : ele;
};

LiveJournal.pollAnswerClick = function(e, data)
{
	if (!data.pollid || !data.pollqid) return false;
	
	var xhr = jQuery.post(LiveJournal.getAjaxUrl('poll'), {
			pollid   : data.pollid,
			pollqid  : data.pollqid,
			page     : data.page,
			pagesize : data.pagesize,
			action   : 'get_answers'
		}, function(data, status) {
			status == 'success' ?
				LiveJournal.pollAnswersReceived(data):
				LiveJournal.ajaxError(data);
	}, 'json');
	
	jQuery(e).hourglass(xhr);
	
	return false;
}

LiveJournal.pollAnswersReceived = function(answers)
{
	if (!answers || !answers.pollid || !answers.pollqid) return;
	
	if (answers.error) return LiveJournal.ajaxError(answers.error);
	
	var id = '#LJ_Poll_' + answers.pollid + '_' + answers.pollqid,
		to_remove = '.LJ_PollAnswerLink, .lj_pollanswer, .lj_pollanswer_paging',
		html = '<div class="lj_pollanswer">' + (answers.answer_html || '(No answers)') + '</div>';
	
	answers.paging_html && (html += '<div class="lj_pollanswer_paging">' + answers.paging_html + '</div>');
	
	jQuery(id).find(to_remove).remove()
		.end().prepend(html).find('.lj_pollanswer').ljAddContextualPopup();
}

// gets a url for doing ajax requests
LiveJournal.getAjaxUrl = function(action, params) {
	// if we are on a journal subdomain then our url will be
	// /journalname/__rpc_action instead of /__rpc_action
	var uselang = LiveJournal.parseGetArgs(location.search).uselang;
	if (uselang) {
		action += "?uselang=" + uselang;
	}
	if (params) {
		action += (uselang ? "&" : "?") + jQuery.param(params);
	}

	return Site.currentJournal
		? "/" + Site.currentJournal + "/__rpc_" + action
		: "/__rpc_" + action;
};

// generic handler for ajax errors
LiveJournal.ajaxError = function (err) {
    if (LJ_IPPU) {
        LJ_IPPU.showNote("Error: " + err);
    } else {
        alert("Error: " + err);
    }
};

// given a URL, parse out the GET args and return them in a hash
LiveJournal.parseGetArgs = function (url) {
    var getArgsHash = {};

    var urlParts = url.split("?");
    if (!urlParts[1]) return getArgsHash;
    var getArgs = urlParts[1].split("&");
    
    for(var arg=0;arg<getArgs.length;arg++){
    	var pair = getArgs[arg].split("=");
        getArgsHash[pair[0]] = pair[1];

    }

    return getArgsHash;
};

LiveJournal.closeSiteMessage = function(node, e, id)
{
	jQuery.post(LiveJournal.getAjaxUrl('close_site_message'), {
			messageid: id
		}, function(data, status) {
			if (status === 'success') {
				jQuery(node.parentNode.parentNode.parentNode).replaceWith(data.substitude);
			} else {
				LiveJournal.ajaxError(data);
			}
		}, 'json');
}
