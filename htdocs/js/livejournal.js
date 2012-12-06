// This file contains general-purpose LJ code
var LiveJournal = {};

// Hooks
;(function ($) {
	'use strict';

	LiveJournal.hooks = {}; // The hook mappings

	/**
	 * Register handler for hook
	 * @param  {String} hook Hook name
	 * @param  {Function} func Hook handler
	 */
	LiveJournal.register_hook = function (hook, func) {
		if (typeof hook !== 'string' || typeof func !== 'function') {
			throw new Error('Provide correct hook name or handler.');
		}

		if ( !LiveJournal.hooks[hook] ) {
			LiveJournal.hooks[hook] = [];
		}

		LiveJournal.hooks[hook].push(func);
	};

	/**
	 * Run registered hooks
	 * @param  {String} hook Hook name
	 */
	LiveJournal.run_hook = function (hook /**, args*/) {
		var hookFuncs = LiveJournal.hooks[hook],
			args = null,
			result = null;

		// nothing has been registered for this hook
		if ( $.type(hookFuncs) !== 'array' || hookFuncs.length === 0 ) {
			return;
		}

		// arguments to pass for the hook
		args = Array.prototype.slice.call(arguments, 1);

		hookFuncs.forEach(function (hookFunc) {
			result = hookFunc.apply(null, args);
		});

		return result;
	};

	/**
	 * Remove hook functionality
	 * @param  {String} hook Hook name
	 * @param  {Function} [func] Hook function to remove
	 */
	LiveJournal.remove_hook = function (hook, func) {
		if (typeof hook !== 'string') {
			throw new Error('Hook name should be provided.');
		}

		// if no hooks has been registered yet
		if (!LiveJournal.hooks[hook]) {
			return;
		}

		if (typeof func === 'function') {
			LiveJournal.hooks[hook] = LiveJournal.hooks[hook].filter(function (hookFunc) {
				return hookFunc !== func;
			});
		} else {
			LiveJournal.hooks[hook] = [];
		}
	};
}(jQuery));

LiveJournal.initPage = function () {
	//LJRU-3137: The code relies on the Site global variable
	//so it appears on all livejournal pages. If it's
	//not there than we are on the external site.
	if (!window.Site) {
		return;
	}

	if (LJ.Api) {
		LJ.Api.init({ auth_token: Site.auth_token });
	}

	LJ.UI.track();

	LJ.UI.bootstrap();

	//register system hooks
	LiveJournal.register_hook('update_wallet_balance', LiveJournal.updateWalletBalance);
	LiveJournal.register_hook('xdr/message', LiveJournal.processXdr);

	// set up various handlers for every page
	LiveJournal.initInboxUpdate();

	LiveJournal.initNotificationStream();
	LiveJournal.initSpoilers();
	LiveJournal.initResizeHelper();

	//ljuniq cookie is checked here now instead of PageStats/Omniture.pm
	LiveJournal.checkLjUniq();

	// run other hooks
	LiveJournal.run_hook('page_load');
};

jQuery(LiveJournal.initPage);

/**
 * Special helper class is added to the body if browser doesn't support media queries and
 * screen width is less then 1000px.
 */
LiveJournal.initResizeHelper = function() {
	var $window = jQuery(window),
		$body = jQuery('body'),
		hasClass = false,
		resizeFunc = LJ.throttle(function() {
			if ($window.width() <= 1000) {
				if (!hasClass) {
					$body.addClass('l-width1000');
					hasClass = true;
				}
			} else if (hasClass) {
				$body.removeClass('l-width1000');
				hasClass = false;
			}
		}, 500);

	//Only older ies need thes (caniuse.com)
	if (jQuery.browser.msie && Number(jQuery.browser.version) <= 8) {
		$window.on('resize', resizeFunc);
		resizeFunc();
	}
};

/**
 * Spoilers functionality - expand hidden text in posts when user clicks on corresponding link
 */
LiveJournal.initSpoilers = function() {
	jQuery(document).delegate('.lj-spoiler > .lj-spoiler-head a', 'click', function (evt) {
		evt.preventDefault();
		jQuery(this).closest('.lj-spoiler').toggleClass('lj-spoiler-opened');
	});
};

/**
 * Init long-polling connection to the server.
 * Now function can be used for testing purposes and
 * should be modified for any real use. E.g. it could be
 * used as an adapter to the Socket.IO
 */
LiveJournal.initNotificationStream = function(force) {
	force = force || false;
	var abortNotifications = false, seed = Site.notifySeed || 0;

	if (Site.notifyDisabled || (!Cookie('ljnotify') && !force && (Math.random() > seed))) {
		return;
	}

	if (!Cookie('ljnotify')) {
		Cookie('ljnotify', '1', {
			domain: Site.siteroot.replace(/^https?:\/\/www\./, ''),
			expires: 5000,
			path: '/'
		});
	}

	LiveJournal.register_hook('notification.stop', function() {
		abortNotifications = true;
	});

	function requestRound() {
		if (abortNotifications) {
			return;
		}

		jQuery.get(LiveJournal.getAjaxUrl('notifications'), 'json').success(
			function(data) {
				//if it's not a notification than it is a timeout answer
				if (data.type === 'notification') {
					LiveJournal.run_hook(data.name, data.params || []);
				}
				requestRound();
			}).error(function() {
				requestRound()
			});
	}

	requestRound();
};

/**
 * Translate message from xdreceiver. The function will eventually be run
 *		from xdreceiver.html helper frame to send messages between different domains.
 *
 * @param {Object} message Object with the message. Object should always contain type field with event name
 */
LiveJournal.processXdr = function(message) {
	if (message.type) {
		var type = decodeURIComponent(message.type);
	} else {
		return;
	}

	var messageCopy = {};
	for (var name in message) {
		if (message.hasOwnProperty(name) && name !== 'type') {
			messageCopy[name] = decodeURIComponent(message[name]);
		}
	}

	LiveJournal.run_hook(type, messageCopy);
};

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
	// Don't run if not logged in or this is disabled
	if (! Site || ! Site.has_remote || ! Site.inbox_update_poll) {
		return;
	}

	// Don't run if no inbox count
	if (!$('LJ_Inbox_Unread_Count')) {
		return;
	}

	// Update every five minutes
	window.setInterval(LiveJournal.updateInbox, 1000 * 60 * 5);
};

// Do AJAX request to find the number of unread items in the inbox
LiveJournal.updateInbox = function () {

	jQuery.post(LiveJournal.getAjaxUrl('esn_inbox'), {
		action: 'get_unread_items'
	}, function(resp) {
		if (! resp || resp.error) {
			return;
		}

		var unread = $('LJ_Inbox_Unread_Count');
		if (unread) {
			unread.innerHTML = resp.unread_count ? '  (' + resp.unread_count + ')' : '';
		} else {
			unread = $('LJ_Inbox_Unread_Count_Controlstrip');
			if (unread) {
				unread.innerHTML = resp.unread_count ? resp.unread_count : '0';
			}
		}
	}, 'json');
};

//refresh number of tokens in the header
LiveJournal.updateWalletBalance = function () {
	jQuery.get(LiveJournal.getAjaxUrl('get_balance'), function(resp) {
		if (! resp || resp.status != 'OK') {
			return;
		}
		var newBalance = resp.balance ? parseInt(resp.balance, 10) : 0;

		var balance = $('LJ_Wallet_Balance');
		if (balance) {
			if (resp.balance) {
				balance.innerHTML = balance.innerHTML.replace(/\d+/, newBalance);
			} else {
				balance.innerHTML = '';
			}
		} else {
			balance = $('LJ_Wallet_Balance_Controlstrip');
			if (balance) {
				balance.innerHTML = newBalance;
			}
		}

		LiveJournal.run_hook('balance_updated', resp.balance);
	}, 'json');
};

// handy utilities to create elements with just text in them
function _textSpan() {
	return _textElements('span', arguments);
}
function _textDiv() {
	return _textElements('div', arguments);
}

function _textElements(eleType, txts) {
	var ele = [];
	for (var i = 0; i < txts.length; i++) {
		var node = document.createElement(eleType);
		node.innerHTML = txts[i];
		ele.push(node);
	}

	return ele.length == 1 ? ele[0] : ele;
}

LiveJournal.pollAnswerClick = function(e, data) {
	if (!data.pollid || !data.pollqid) {
		return false;
	}

	var xhr = jQuery.post(LiveJournal.getAjaxUrl('poll'), {
		pollid	 : data.pollid,
		pollqid	 : data.pollqid,
		page		 : data.page,
		pagesize : data.pagesize,
		action	 : 'get_answers'
	}, function(data, status) {
		status == 'success' ? LiveJournal.pollAnswersReceived(data) : LiveJournal.ajaxError(data);
	}, 'json');

	jQuery(e).hourglass(xhr);

	return false;
};

LiveJournal.pollAnswersReceived = function(answers) {
	if (!answers || !answers.pollid || !answers.pollqid) {
		return;
	}

	if (answers.error) {
		return LiveJournal.ajaxError(answers.error);
	}

	var id = '#LJ_Poll_' + answers.pollid + '_' + answers.pollqid,
		to_remove = '.LJ_PollAnswerLink, .lj_pollanswer, .lj_pollanswer_paging',
		html = '<div class="lj_pollanswer">' + (answers.answer_html || '(No answers)') + '</div>';

	answers.paging_html && (html += '<div class="lj_pollanswer_paging">' + answers.paging_html + '</div>');

	jQuery(id)
		.find(to_remove)
		.remove()
		.end()
		.prepend(html)
		.find('.lj_pollanswer')
		.ljAddContextualPopup();
};

// gets a url for doing ajax requests
LiveJournal.getAjaxUrl = function(action, params) {
	// if we are on a journal subdomain then our url will be
	// /journalname/__rpc_action instead of /__rpc_action
	var uselang = LiveJournal.parseGetArgs(location.search).uselang;
	if (uselang) {
		action += '?uselang=' + uselang;
	}
	if (params) {
		action += (uselang ? '&' : '?') + jQuery.param(params);
	}

	return Site.currentJournal ? '/' + Site.currentJournal + '/__rpc_' + action : '/__rpc_' + action;
};

// generic handler for ajax errors
LiveJournal.ajaxError = function (err) {
	if (LJ_IPPU) {
		LJ_IPPU.showNote('Error: ' + err);
	} else {
		alert('Error: ' + err);
	}
};

// given a URL, parse out the GET args and return them in a hash
LiveJournal.parseGetArgs = function (url) {
	url = url || window.location.href;
	url = url.replace(/#.*$/, '');

	var getArgsHash = {};

	var urlParts = url.split('?');
	if (!urlParts[1]) {
		return getArgsHash;
	}
	var getArgs = urlParts[1].split('&');

	for (var arg = 0; arg < getArgs.length; arg++) {
		var pair = getArgs[arg].split('=');
		getArgsHash[pair[0]] = pair[1];

	}

	return getArgsHash;
};

/**
 * Construct an url from base string and params object.
 *
 * @param {String} base Base string.
 * @param {Object} args Object with arguments, that have to be passed with the url.
 * @return {String}
 */
LiveJournal.constructUrl = function(base, args, escapeArgs) {
	base = base.replace(/(\&|\?)+$/g, '');
	var queryStr = base,
		queryArr = [];

	if (args) {
		queryStr += ( base.indexOf('?') === -1 ? '?' : '&' );

		for (var i in args) {
			queryArr.push(i + '=' + ( ( escapeArgs ) ? encodeURIComponent(args[i]) : args[i] ));
		}
	}

	return queryStr + queryArr.join('&');
};

/**
 * Generate a string for ljuniq cookie
 *
 * @return {String}
 */
LiveJournal.generateLjUniq = function() {
	var alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', result = '', i;

	var len = 15;
	for (i = 0; i < len; ++i) {
		result += alpha.charAt(Math.floor(Math.random() * ( alpha.length - 1 )));
	}

	result += ':' + Math.floor((new Date()) / 1000);
	result += ':pgstats' + ( ( Math.random() < 0.05 ) ? '1' : '0' );

	return result;
};

LiveJournal.checkLjUniq = function() {
	if (!Cookie('ljuniq')) {
		Cookie('ljuniq', LiveJournal.generateLjUniq(), {
				domain: Site.siteroot.replace(/^https?:\/\/www\./, ''),
				expires: 5000,
				path: '/'
			});
	}
};

LiveJournal.closeSiteMessage = function(node, e, id) {
	jQuery.post(LiveJournal.getAjaxUrl('close_site_message'), {
		messageid: id
	}, function(data, status) {
		if (status === 'success') {
			jQuery(node.parentNode.parentNode.parentNode).replaceWith(data.substitude);
		} else {
			LiveJournal.ajaxError(data);
		}
	}, 'json');
};

LiveJournal.parseLikeButtons = (function ($) {
	'use strict';

	var selectors = {
		facebook: '.lj-like-item-facebook',
		google: '.lj-like-item-google',
		twitter: '.lj-like-item-twitter',
		tumblr: '.lj-like-item-tumblr',
		surfingbird: '.lj-like-item-surfinbird',
		repost: '.lj-like-item-repost'
	};

	/**
	 * Parse lj-like buttons
	 * @param  {Object} $node jQuery .lj-like node
	 */
	function parse($node) {
		parseFacebook($node);
		parseGoogle($node);
		parseTwitter($node);
		parseTumblr($node);
		parseSurfingbird($node);
		parseRepost($node);
	}

	/**
	 * Create iframe node with default params and ability to redefine them (iframe factory)
	 * @param  {Object} params Params to substitute for iframe {src, width, height...}
	 * @return {Element}       Created iframe node
	 */
	function createIframe(params) {
		var iframe = document.createElement('iframe'),
			param;

		// defaults
		iframe.frameBorder = 0;
		iframe.scrolling = 'no';
		iframe.allowTransparency = 'true';
		iframe.width = 110;
		iframe.height = 20;

		// reassign params
		if (params) {
			for (param in params) {
				if (params.hasOwnProperty(param)) {
					iframe[param] = params[param];
				}
			}
		}

		return iframe;
	}

	/**
	 * Parse facebook likes
	 * Documentation: http://developers.facebook.com/docs/reference/javascript/FB.XFBML.parse/
	 * @param  {jQuery} $node jQuery collection
	 */
	function parseFacebook($node) {
		var item = $node.find( selectors.facebook );

		if (item.length === 0) {
			return;
		}

		try {
			window.FB.XFBML.parse( item.get(0) );
		} catch (e) {
			console.warn(e.message);
		}
	}

	/**
	 * Parse google +1 button
	 * Documentation: https://developers.google.com/+/plugins/+1button/#jsapi
	 * @param  {jQuery} $node jQuery node with likes in which we will search for google +1 button for parsing
	 */
	function parseGoogle($node) {
		var $button = $node.find( selectors.google ).children().first(),	// jquery node <g:plusone />
			button = null;	// raw DOM node <g:plusone>

		if ($button.length === 0) {
			return;
		}

		button = $button.get(0);

		// gapi could throw errors
		try {
			window.gapi.plusone.render( button, { size: $button.attr('size'), href: $button.attr('href') } );
		} catch (e) {
			console.warn(e.message);
		}
	}

	/**
	 * Parse and replace twitter button
	 * @param  {jQuery} $node jQuery node with .lj-like class
	 */
	function parseTwitter($node) {
		var params = null,
			iframe = null,
			// link to replace with iframe
			link = null,
			item = $node.find( selectors.twitter );

		if (item.length === 0) {
			return;
		}

		link = item.children().eq(0);

		params = {
			url: link.data('url'),
			text: link.data('text'),
			count: link.data('count'),
			lang: link.data('lang')
		};

		iframe = createIframe({
			src: LiveJournal.constructUrl('http://platform.twitter.com/widgets/tweet_button.html', params)
		});

		link.replaceWith(iframe);
	}

	/**
	 * Parse surfingbird share button
	 * @param  {jQuery} $node jQuery .lj-like node
	 */
	function parseSurfingbird($node) {
		var item = $node.find( selectors.surfingbird ),
			link = null,
			iframe = null,
			params = null;

		if (item.length === 0) {
			return;
		}

		link = item.find('.surfinbird__like_button');
		params = {
			url: link.data('url'),
			caption: link.data('text'),
			layout: 'common'
		};

		iframe = createIframe({
			src: LiveJournal.constructUrl('http://surfingbird.ru/button', params)
		});

		link.replaceWith(iframe);
	}

	/**
	 * Parse tumblr share button
	 * @param  {jQuery} $node jQuery .lj-like node
	 */
	function parseTumblr($node) {
		var item = $node.find( selectors.tumblr ),
			link = null,
			params = null,
			href;

		if (item.length === 0) {
			return;
		}

		link = item.find('.tumblr-share-button'),
		href = link.attr('href'),
		params = {
			url: link.data('url'),
			name: link.data('title')
		};

		link.attr('href', LiveJournal.constructUrl(href, params));
	}

	/**
	 * Parse repost button
	 * @param  {jQuery} $node jQuery .lj-like node
	 */
	function parseRepost($node) {
		var item = $node.find( selectors.repost ),
			link = null,
			url;

		if (item.length === 0) {
			return;
		}

		link = $node.find('.lj-like-item-repost').find('a'),
		url = link.data('url');

		LJ.Api.call('repost.get_status', { url: url }, function (data) {
			link.replaceWith(LiveJournal.renderRepostButton(url, data));
		});
	}

	return parse;
}(jQuery));

LiveJournal.renderRepostButton = function (url, data) {
	data = data || {};

	var meta = {
			paid: !!data.paid,
			url: url,
			cost: data.cost,
			budget: data.budget,
			count: Number(data.count || 0),
			reposted: !!data.reposted
		},
		template = 'templates-CleanHtml-Repost',
		options = {},
		node;

	if (meta.paid) {
		template = 'templates-CleanHtml-PaidRepost';
		meta.owner = meta.cost === '0';
		options.classNames = {
			active: 'paidrepost-button-active',
			inactive: 'paidrepost-button-inactive'
		};
	}

	return LJ.UI.template(template, meta).repostbutton(jQuery.extend(options, meta));
};

/**
 * Insert script in the document.
 *
 * @param {String} url Url of the script
 * @param {Object=} params Data to apply to the scipt node object, e.g. async, text.
 * @param {Node=} parent If exists, script tag will be inserted in this node or before the
 *		 first script tag otherwise.
 */
LiveJournal.injectScript = function(url, params, parent) {

	function loadScript() {
		var defaults = {
			async: true
		};

		params = params || {};
		params = jQuery.extend({}, defaults, params);

		var e = document.createElement('script');
		e.src = url;

		for (var i in params) {
			if (params.hasOwnProperty(i)) {
				e[i] = params[i];
			}
		}

		if (parent) {
			parent.appendChild(e);
		} else {
			s = document.getElementsByTagName('script')[0];
			s.parentNode.insertBefore(e, s);
		}
	}

	//opera doesn't support async attribute, so we load the scrips on onload event to display page faster
	if (jQuery.browser.opera) {
		jQuery(loadScript);
	} else {
		loadScript();
	}
};

LiveJournal.getLocalizedStr = LJ.ml;

LiveJournal.JSON = function() {
	/**
	 * Formats integers to 2 digits.
	 * @param {number} n
	 * @private
	 */
	function f(n) {
		return n < 10 ? '0' + n : n;
	}

	Date.prototype.toJSON = function() {
		return [this.getUTCFullYear(), '-',
			f(this.getUTCMonth() + 1), '-',
			f(this.getUTCDate()), 'T',
			f(this.getUTCHours()), ':',
			f(this.getUTCMinutes()), ':',
			f(this.getUTCSeconds()), 'Z'].join('');
	};

	// table of character substitutions
	/**
	 * @const
	 * @enum {string}
	 */
	var m = {
		'\b': '\\b',
		'\t': '\\t',
		'\n': '\\n',
		'\f': '\\f',
		'\r': '\\r',
		'"' : '\\"',
		'\\': '\\\\'
	};

	/**
	 * Converts a json object into a string.
	 * @param {*} value
	 * @return {string}
	 * @member gadgets.json
	 */
	function stringify(value) {
		var a, // The array holding the partial texts.
			i, // The loop counter.
			k, // The member key.
			l, // Length.
			r = /["\\\x00-\x1f\x7f-\x9f]/g, v;					// The member value.

		switch (typeof value) {
			case 'string':
				// If the string contains no control characters, no quote characters, and no
				// backslash characters, then we can safely slap some quotes around it.
				// Otherwise we must also replace the offending characters with safe ones.
				return r.test(value) ? '"' + value.replace(r, function(a) {
					var c = m[a];
					if (c) {
						return c;
					}
					c = a.charCodeAt();
					return '\\u00' + Math.floor(c / 16).toString(16) + (c % 16).toString(16);
				}) + '"' : '"' + value + '"';
			case 'number':
				// JSON numbers must be finite. Encode non-finite numbers as null.
				return isFinite(value) ? String(value) : 'null';
			case 'boolean':
			case 'null':
				return String(value);
			case 'object':
				// Due to a specification blunder in ECMAScript,
				// typeof null is 'object', so watch out for that case.
				if (!value) {
					return 'null';
				}
				// toJSON check removed; re-implement when it doesn't break other libs.
				a = [];
				if (typeof value.length === 'number' && !value.propertyIsEnumerable('length')) {
					// The object is an array. Stringify every element. Use null as a
					// placeholder for non-JSON values.
					l = value.length;
					for (i = 0; i < l; i += 1) {
						a.push(stringify(value[i]) || 'null');
					}
					// Join all of the elements together and wrap them in brackets.
					return '[' + a.join(',') + ']';
				}
				// Otherwise, iterate through all of the keys in the object.
				for (k in value) {
					if (k.match('___$')) {
						continue;
					}
					if (value.hasOwnProperty(k)) {
						if (typeof k === 'string') {
							v = stringify(value[k]);
							if (v) {
								a.push(stringify(k) + ':' + v);
							}
						}
					}
				}
				// Join all of the member texts together and wrap them in braces.
				return '{' + a.join(',') + '}';
		}
		return '';
	}

	return window.JSON || {
		'stringify': stringify,
		'parse': function(text) {
			// Parsing happens in three stages. In the first stage, we run the text against
			// regular expressions that look for non-JSON patterns. We are especially
			// concerned with '()' and 'new' because they can cause invocation, and '='
			// because it can cause mutation. But just to be safe, we want to reject all
			// unexpected forms.

			// We split the first stage into 4 regexp operations in order to work around
			// crippling inefficiencies in IE's and Safari's regexp engines. First we
			// replace all backslash pairs with '@' (a non-JSON character). Second, we
			// replace all simple value tokens with ']' characters. Third, we delete all
			// open brackets that follow a colon or comma or that begin the text. Finally,
			// we look to see that the remaining characters are only whitespace or ']' or
			// ',' or ':' or '{' or '}'. If that is so, then the text is safe for eval.

			if (/^[\],:{}\s]*$/.test(text.replace(/\\["\\\/b-u]/g, '@').replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, ']').replace(/(?:^|:|,)(?:\s*\[)+/g, ''))) {
				return eval('(' + text + ')');
			}
			// If the text is not JSON parseable, then return false.

			return false;
		}
	};
}();

/**
 * Check if site if browsed by mobile device
 *
 */
LiveJournal.isMobile = function() {
	var agent = navigator.userAgent || navigator.vendor || window.opera, isMobile = /android.+(mobile|transformer)|avantgo|bada\/|blackberry|blazer|compal|elaine|fennec|hiptop|iemobile|ip(hone|od|ad)|iris|kindle|lge |maemo|midp|mmp|opera m(ob|in)i|opera tablet|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|symbian|treo|up\.(browser|link)|vodafone|wap|windows (ce|phone)|xda|xiino/i.test(agent) || /1207|6310|6590|3gso|4thp|50[1-6]i|770s|802s|a wa|abac|ac(er|oo|s\-)|ai(ko|rn)|al(av|ca|co)|amoi|an(ex|ny|yw)|aptu|ar(ch|go)|as(te|us)|attw|au(di|\-m|r |s )|avan|be(ck|ll|nq)|bi(lb|rd)|bl(ac|az)|br(e|v)w|bumb|bw\-(n|u)|c55\/|capi|ccwa|cdm\-|cell|chtm|cldc|cmd\-|co(mp|nd)|craw|da(it|ll|ng)|dbte|dc\-s|devi|dica|dmob|do(c|p)o|ds(12|\-d)|el(49|ai)|em(l2|ul)|er(ic|k0)|esl8|ez([4-7]0|os|wa|ze)|fetc|fly(\-|_)|g1 u|g560|gene|gf\-5|g\-mo|go(\.w|od)|gr(ad|un)|haie|hcit|hd\-(m|p|t)|hei\-|hi(pt|ta)|hp( i|ip)|hs\-c|ht(c(\-| |_|a|g|p|s|t)|tp)|hu(aw|tc)|i\-(20|go|ma)|i230|iac( |\-|\/)|ibro|idea|ig01|ikom|im1k|inno|ipaq|iris|ja(t|v)a|jbro|jemu|jigs|kddi|keji|kgt( |\/)|klon|kpt |kwc\-|kyo(c|k)|le(no|xi)|lg( g|\/(k|l|u)|50|54|e\-|e\/|\-[a-w])|libw|lynx|m1\-w|m3ga|m50\/|ma(te|ui|xo)|mc(01|21|ca)|m\-cr|me(di|rc|ri)|mi(o8|oa|ts)|mmef|mo(01|02|bi|de|do|t(\-| |o|v)|zz)|mt(50|p1|v )|mwbp|mywa|n10[0-2]|n20[2-3]|n30(0|2)|n50(0|2|5)|n7(0(0|1)|10)|ne((c|m)\-|on|tf|wf|wg|wt)|nok(6|i)|nzph|o2im|op(ti|wv)|oran|owg1|p800|pan(a|d|t)|pdxg|pg(13|\-([1-8]|c))|phil|pire|pl(ay|uc)|pn\-2|po(ck|rt|se)|prox|psio|pt\-g|qa\-a|qc(07|12|21|32|60|\-[2-7]|i\-)|qtek|r380|r600|raks|rim9|ro(ve|zo)|s55\/|sa(ge|ma|mm|ms|ny|va)|sc(01|h\-|oo|p\-)|sdk\/|se(c(\-|0|1)|47|mc|nd|ri)|sgh\-|shar|sie(\-|m)|sk\-0|sl(45|id)|sm(al|ar|b3|it|t5)|so(ft|ny)|sp(01|h\-|v\-|v )|sy(01|mb)|t2(18|50)|t6(00|10|18)|ta(gt|lk)|tcl\-|tdg\-|tel(i|m)|tim\-|t\-mo|to(pl|sh)|ts(70|m\-|m3|m5)|tx\-9|up(\.b|g1|si)|utst|v400|v750|veri|vi(rg|te)|vk(40|5[0-3]|\-v)|vm40|voda|vulc|vx(52|53|60|61|70|80|81|83|85|98)|w3c(\-| )|webc|whit|wi(g |nc|nw)|wmlb|wonu|x700|xda(\-|2|g)|yas\-|your|zeto|zte\-/i.test(agent.substr(0, 4));

	var forceMobile = false, item;
	if (window.localStorage) {
		item = localStorage.getItem('forceMobile');
		forceMobile = item === '1';
	}
	return function() {
		return forceMobile || isMobile;
	}
}();

LiveJournal.getEmbed = function(url) {
	var text = url,
		videoid;

	if (text.match(/^(http:\/\/(www\.)?)?youtu\.be/)) {
		videoid = (text.split('?')[0]).replace(/\/+$/,'').split('/').pop();
		text = 'http://www.youtube.com/embed/' + videoid;
		text = '<iframe width="490" height="370" src="{text}" frameborder="0" allowfullscreen data-link="{url}"></iframe>'.supplant({ text: text, url: url });
	} else if (text.match(/^(http:\/\/(www\.)?)?youtube\.com/)) {
		text = 'http://www.youtube.com/embed/' + LiveJournal.parseGetArgs(text).v;
		text = '<iframe width="490" height="370" src="{text}" frameborder="0" allowfullscreen data-link="{url}"></iframe>'.supplant({ text: text, url: url });
	} else if (text.match(/^(http:\/\/(www\.)?)?rutube\.ru/)) {
		text = 'http://video.rutube.ru/' + LiveJournal.parseGetArgs(text).v;
		text = ('<lj-embed> <OBJECT width="470" height="353">' +
				'<PARAM name="movie" value="{text}"></PARAM>' +
				'<PARAM name="wmode" value="window"></PARAM><PARAM name="allowFullScreen" value="true"></PARAM>' +
				'<EMBED src="{text}" type="application/x-shockwave-flash"' +
				' wmode="window" width="470" height="353" allowFullScreen="true" ></EMBED></OBJECT></lj-embed>').supplant({ text: text });
	} else if (text.match(/^(http:\/\/(www\.)?)?vimeo\.com/)) {
		videoid = (text.split('?')[0]).replace(/\/+$/,'').split('/').pop();
		text = 'http://player.vimeo.com/video/' + videoid;
		text = ('<iframe src="{text}" width="400" height="225" frameborder="0"' +
			'webkitAllowFullScreen mozallowfullscreen allowFullScreen data-link="{url}"></iframe>').supplant({ text: text, url: url });
	}
	return text;
};

LiveJournal.parseMediaLink = function(input) {
	'use strict';

	var regexp = /^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#\&\?]*).*/;
	var match = input.match(regexp);

	if (match && match[7]) {
		var id = match[7];
		return {
			id: id,
			site: 'youtube',
			preview: 'http://img.youtube.com/vi/' + id + '/0.jpg'
		};
	}
	return null;
};
