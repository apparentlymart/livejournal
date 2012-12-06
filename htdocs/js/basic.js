document.documentElement.id = 'js';

/* Cookie plugin. Copyright (c) 2006 Klaus Hartl (stilbuero.de) */
function Cookie(name, value, options)
{
	if (value !== undefined) { // name and value given, set/delete cookie
		options = options || {};
		if (value === null) {
			value = '';
			options.expires = -1;
		}
		var expires = '';
		if (options.expires && (typeof options.expires == 'number' || options.expires.toUTCString)) {
			var date;
			if (typeof options.expires == 'number') {
				date = new Date;
				date.setTime(date.getTime() + (options.expires * 24 * 60 * 60 * 1000));
			} else {
				date = options.expires;
			}
			expires = '; expires=' + date.toUTCString(); // use expires attribute, max-age is not supported by IE
		}
		// CAUTION: Needed to parenthesize options.path and options.domain
		// in the following expressions, otherwise they evaluate to undefined
		// in the packed version for some reason...
		var path = options.path ? '; path=' + (options.path) : '',
			domain = options.domain ? '; domain=' + (options.domain) : '',
			secure = options.secure ? '; secure' : '',
			cookieValue = [name, '=', encodeURIComponent(value), expires, path, domain, secure].join('');
		document.cookie = cookieValue;
		return cookieValue;
	} else { // only name given, get cookie
		var cookieValue = null;
		if (document.cookie && document.cookie != '') {
			var cookies = document.cookie.split(';');
			for (var i = 0; i < cookies.length; i++) {
				var cookie = cookies[i].trim();
				// Does this cookie string begin with the name we want?
				if (cookie.substring(0, name.length + 1) == (name + '=')) {
					cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
					break;
				}
			}
		}
		return cookieValue;
	}
}

//core.js

/**
 * Utility method.
 * @param x <code>any</code> Any JavaScript value, including <code>undefined</code>.
 * @return boolean <code>true</code> if the value is not <code>null</code> and is not <code>undefined</code>.
 */
finite = function(x){
	return isFinite(x) ? x : 0;
};


finiteInt = function(x, base){
	return finite(parseInt(x, base));
};


finiteFloat = function(x){
	return finite(parseFloat(x));
};

/* unique id generator */
Unique = {
	length: 0,
	id: function(){
		return ++this.length;
	}
};

/* event methods */
var Event = Event||{};

Event.stop = function(e){
	// this set in Event.prep
	e = e || window.event || this;
	Event.stopPropagation(e);
	Event.preventDefault(e);
	return false;
};

Event.stopPropagation = function(e){
	if(e && e.stopPropagation)
		e.stopPropagation(); else
		window.event.cancelBubble = true;
};

Event.preventDefault = function(e){
	e = e || window.event;
	if(e.preventDefault)
		e.preventDefault();
	e.returnValue = false;
};

Event.prep = function(e){
	e = e || window.event;
	if(e.stop === undefined)
		e.stop = this.stop;
	if(e.target === undefined)
		e.target = e.srcElement;
	if(e.relatedTarget === undefined)
		e.relatedTarget = e.toElement;
	return e;
};

/**
 * @namespace LJ LiveJournal utility objects
 */
LJ = window.LJ || {};

/**
 * Define a namespace.
 *
 * @param {string} path The String with namespace to be created.
 * @param {Object=} top An optional object. If set then the namespace will be built relative to it. Defaults to the window.
 */
LJ.define = function(path, top) {
	var ns = path.split('.'),
		name;

	top = top || window;

	while (name = ns.shift()) {
		top[name] = top[name] || {};
		top = top[name];
	}

}

/**
 * Mark the namespace as a dependency. The function does nothing now.
 *
 * @param {string} path Namespace name.
 */
LJ.require = function(path) {
	//fillme
};

/**
 * Get a variable, defined especially for this page in the Site.page.
 *
 * @param {string} name Variable name.
 * @param {boolean} global A flag to check, whether the variable is local to page or not.
 *
 * @return {*} Returns a page variable or undefined if not found.
 */
LJ.pageVar = function(name, global) {
	var obj = global ? window.Site : window.Site.page;

	if (obj && obj.hasOwnProperty(name)) {
		return obj[name];
	} else {
		return void(0);
	}
};

/**
 * @class Class allows to call a function with  some delay and also prevent
 *     its execution if needed.
 * @constructor
 *
 * @param {Function} func Function to call.
 * @param {number} wait Time in ms to wait before function will be called.
 * @param {boolean=false} resetOnCall it true, the function will be executed only after last call + delay time
 */
LJ.DelayedCall = function(func, wait, resetOnCall) {
	this._func = func;
	this._wait = wait;
	this._resetOnCall = !!resetOnCall;
	this._timer = null;
	this._args = null;
};

LJ.DelayedCall.prototype._timerCallback = function() {
	this._timer = null;
	this._func.apply(null, this._args);
};

/**
 * Run function. All arguments that will be passed to this function will be
 *    passed to the function called.
 */
LJ.DelayedCall.prototype.run = function(/* arguments */) {
	this._args = [].slice.call(arguments, 0);
	if (this._timer) {
		if (this._resetOnCall) {
			clearTimeout(this._timer);
			this._timer = null;
		} else {
			return;
		}
	}

	this._timer = setTimeout(this._timerCallback.bind(this), this._wait);
};

/**
 * Prevent function execution.
 */
LJ.DelayedCall.prototype.stop = function() {
	clearTimeout(this._timer);
	this._timer = null;
};

/**
 * Format number according to locale. E.g. 1000000 becomes 1,000,000.
 *
 * @param {number} num Number to format.
 */
LJ.commafy = function(num) {
	num = "" + num;
	if (/^\d+$/.test(num)) {
		var delim = LiveJournal.getLocalizedStr('number.punctuation');
		if (delim === '[number.punctuation]') { delim = ','; }

		var hasMatches = true;
		while (hasMatches) {
			hasMatches = false;
			num = num.replace(/(\d)(\d{3})(?!\d)/g, function(str, first, group) {
				hasMatches = true;
				return first + delim + group;
			})
		}
	}

	return num;
};

/**
 * Create function that will call the target function
 * at most once per every delay seconds. The signature and tests
 * are taken from underscore project.
 *
 * @param {Function} func The function to call.
 * @param {number} Delay between the calls in ms.
 */
LJ.throttle = function(func, delay) {
	var ctx, args, timer, shouldBeCalled = false;

	return function() {
		ctx = this;
		args = arguments;

		var callFunc = function() {
			timer = null;
			if (!shouldBeCalled) { return; }
			shouldBeCalled = false;
			timer = setTimeout(callFunc, delay);
			var ret = func.apply(ctx, args);

			return ret;
		};

		shouldBeCalled = true;
		if (timer) { return; }

		return callFunc();
	};
};

/**
 * Returns a function, that, as long as it continues to be invoked, will not
 * be triggered. The function will be called after it stops being called for
 * N milliseconds. If `immediate` is passed, trigger the function on the
 * leading edge, instead of the trailing.
 *
 * Notice: signature and documentation has been taken from `underscore` project
 *
 * @param  {Function} func    Function to be called
 * @param  {Number} wait      Amount of milliseconds to wait before invocation
 * @param  {Boolean} [immediate] Invocation edge
 * @return {Function}           Debounced function `func`
 */
LJ.debounce = function (func, wait, immediate) {
	'use strict';

	var timeout, result;

	return function () {
		var context = this,
			args = arguments,
			later,
			callNow = immediate && !timeout;

		later = function() {
			timeout = null;
			if ( !immediate ) {
				result = func.apply(context, args);
			}
		};

		clearTimeout(timeout);
		timeout = setTimeout(later, wait);

		if (callNow) {
			result = func.apply(context, args);
		}

		return result;
	};
},

/**
 * Create function that will call target function at most once
 * per every delay. Arguments are queued and when delay ends
 * function is called with last supplied arguments set. Optionally
 * arguments queue can be preserved on call, so all sheduled will be done.
 *
 * @param {Function} f The function to call.
 * @param {Number} delay Delay between the calls in ms.
 * @param {Boolean} preserve Run all queued sequentially
 */

LJ.threshold = function (f, delay, preserve) {
	var queue = [],
		batchSize, batch,
		lock = false,

		callback = function () {
			var caller = this;

			if (lock || !queue.length) {
				return;
			}

			while (queue.length) {
				lock = true;

				if (preserve) {
					f.apply(caller, queue.shift());
				} else {
					f.apply(caller, queue.pop());
					queue = [];
				}

				if (batch && --batch) {
					lock = false;
					continue;
				}

				setTimeout(function () {
					lock = false;
					batch = batchSize;
					callback.call(caller);
				}, delay);

				break;
			}
		},

		threshold = function () {
			queue.push([].slice.call(arguments));
			callback.call(this);
		};

	threshold.resetQueue = function () {
		queue = [];
	};

	threshold.batch = function (size) {
		if (size !== undefined) {
			batchSize = size >>> 0;
			if (!lock) {
				batch = batchSize;
			}
		}
	};

	return threshold;
};

if (typeof console !== 'undefined') {
	LJ.console = console;
}

LJ._const = {};

/**
 * Define a constant.
 *
 * @param {string} name name of the constant. All spaces will be replaced with underline.
 *     if constant was already defined, the function will throw the exception.
 * @param {*} value A value of the constant.
 */
LJ.defineConst = function(name, value) {
	name = name.toUpperCase().replace(/\s+/g, '_');

	if (LJ._const.hasOwnProperty(name)) {
		throw new Error('constant was already defined');
	} else {
		LJ._const[name] = value;
	}
};

/**
 * Get the value of the constant.
 *
 * @param {string} name The name of the constant.
 * @return {*} The value of the constant or undefined if constant was not defined.
 */
LJ.getConst = function(name) {
	name = name.toUpperCase().replace(/\s+/g, '_');

	return (LJ._const.hasOwnProperty(name) ? LJ._const[name] : void 0);
};

/**
 * @namespace LJ.Util.Journal Utility functions connected with journal
 */
LJ.define('LJ.Util.Journal');

(function() {
	var base = (LJ.pageVar('siteroot', true) || 'http://www.livejournal.com')
						.replace('http://www', ''),
		journalReg  = new RegExp('^http:\\/\\/([\\w-]+)' + base.replace(/\./, '\\.') + '(?:\\/(?:([\\w-]+)\\/)?(?:(\\d+)\\.html)?)?$');

	/**
	 * Parse journal link to retrieve information from it
	 *
	 * @param {string} url The string to parse.
	 * @return {Object} Return object will contain fields journal and ditemid(if availible) or null if the link cannot be parsed.
	 */
	LJ.Util.Journal.parseLink = function(url) {
		if (!url) {
			return null;
		}

		if (!url.match(/(\.html|\/)$/)) {
			url += '/';
		}

		var regRes = journalReg.exec(url),
			result = {};

		if (!regRes || !regRes[1]) { return null; }

		if (!regRes[1].match(/^(?:users|community)$/)) {
			result.journal = regRes[1];
		} else {
			if (!regRes[2]) { return null; }
			result.journal = regRes[2];
		}

			result.journal = result.journal.replace(/-/g, '_');

		if (regRes[3]) {
			result.ditemid = parseInt(regRes[3], 10);
		}

		return result;
	};

	/**
	 * Render journal link according to the standard scheme.
	 *
	 * @param {string} journal Journal name.
	 * @param {string|number}  ditemid Id of the post in the journal.
	 * @param {boolean} iscomm Whether to treat the journal as community.
	 *
	 * @return {string|null} Result is a link to the journal page or null if no journal was specified.
	 */
	LJ.Util.Journal.renderLink = function(journal, ditemid, iscomm) {
		if (!journal) {
			return null;
		}

		var url = 'http://';
		if (iscomm) {
			url += 'community' + base + '/' + journal;
		} else if (journal.match(/^_|_$/)) {
			url += 'users' + base + '/' + journal;
		} else {
			url += journal.replace(/_/g, '-') + base;
		}

		url += '/';

		if (ditemid) {
			url += ditemid + '.html';
		}

		return url;
	};

}());

/**
 * @namespace LJ.Util.Date The namespace contains utility functions connected with date.
 */
LJ.define('LJ.Util.Date');

(function() {

	var months = [ 'january', 'february', 'march', 'april',
					'may', 'june', 'july', 'august',
					'september', 'october', 'november', 'december' ],
		month_ml = 'date.month.{month}.long';

	function normalizeFormat(format) {
		if (!format || format === 'short') {
			format = LiveJournal.getLocalizedStr('date.format.short');
		} else if (format === 'long') {
			format = LiveJournal.getLocalizedStr('date.format.long');
		}

		return format;
	}

	function getMonth(idx) {
		var month = months[ idx % 12 ];
		return LiveJournal.getLocalizedStr(month_ml.supplant({month: month}));
	}

	/**
	 * Parse date from string.
	 *
	 * @param {string} datestr The string containing the date.
	 * @param {string} format Required date string format.
	 */
	LJ.Util.Date.parse = function(datestr, format) {
		format = normalizeFormat(format);

		//don't touch it if you can't use it
		if (!datestr) { return datestr; }

		var testStr = normalizeFormat(format),
			positions = [ null ],
			pos = 0, token,
			regs = {
				'%Y' : '(\\d{4})',
				'%M' : '(\\d{2})',
				'%D' : '(\\d{2})'
			};

		while( ( pos = testStr.indexOf( '%', pos ) ) !== -1 ) {
			token = testStr.substr( pos, 2 );
			if( token in regs ) {
				testStr = testStr.replace( token, regs[ token ] );
				positions.push( token );
			} else {
				pos += 2; //skip this token
				positions.push( null );
			}
		}

		var r = new RegExp( testStr ),
			arr = r.exec( datestr );

		if( !arr ) {
			return null;
		} else {
			var d = new Date();
			for( var i = 1; i < arr.length; ++i ) {
				if( positions[ i ] ) {
					switch( positions[ i ] ) {
						case '%D':
							d.setDate( arr[ i ] );
							break;
						case '%M':
							d.setMonth( parseInt( arr[ i ], 10 ) - 1 );
							break;
						case '%Y':
							d.setFullYear( arr[ i ] );
							break;
					}
				}
			}

			return d;
		}
	};

	/**
	 * Create string representation of object according to the format.
	 *
	 * @param {Date} date The date object to work with.
	 * @param {string=} format String format. Possible default formats are 'short' and 'long'.
	 */
	LJ.Util.Date.format = function(date, format) {
		format = normalizeFormat(format);

		return format.replace( /%([a-zA-Z]{1})/g, function(str, letter) {
			switch (letter) {
				case 'M' :
					return ('' + (date.getMonth() + 1)).pad(2, '0');
				case 'B' : //full month
					return getMonth(date.getMonth());
				case 'D' :
					return ('' + date.getDate()).pad(2, '0');
				case 'Y' :
					return date.getFullYear();
				case 'R' :
					return ('' + date.getHours()).pad(2, '0') + ':' + ('' + date.getMinutes()).pad(2, '0');
				case 'T' :
					return [
						('' + date.getHours()).pad(2, '0'),
						('' + date.getMinutes()).pad(2, '0'),
						('' + date.getSeconds()).pad(2, '0')
					].join(':');
				default:
					return str;
			}
		});
	};

	/**
	 * Get timezone from the date object in the canonical way.
	 *
	 * @return {string} A string representation of timezone, eg +0400
	 */
	LJ.Util.Date.timezone = function() {
		var offset = (-(new Date()).getTimezoneOffset() / 0.6),
			str = '';

		if (offset > 0) {
			str += '+';
		} else if (offset < 0) {
			str += '-';
			offset = -offset;
		}

		str += ('' + offset).pad(4, '0');

		return str;
	};

}());


LJ.DOM = LJ.DOM || {};

/**
 * Inject stylesheet into page.
 *
 * @param {string} Stylesheet filename to inject.
 * @param {global} Global object.
 */
LJ.DOM.injectStyle = function(fileName, _window) {
	var w = _window || window,
		head = w.document.getElementsByTagName("head")[0],
		cssNode = w.document.createElement('link');

	cssNode.type = 'text/css';
	cssNode.rel = 'stylesheet';
	cssNode.href = fileName;

	head.appendChild(cssNode);
};

/**
 * Get field's selection
 * @param  {jQuery/DOM} node jQuery or DOM node
 * @return {Object}      Object, contains { start, end } coordinates of selection
 */
LJ.DOM.getSelection = function (node) {
	var start = 0,
		end = 0,
		range,
		dup,
		regexp = null;

	if (!node.nodeName) {
		node = node.get(0);
	}

	if ( 'selectionStart' in node ) {
		return {
			start: node.selectionStart,
			end: node.selectionEnd
		};
	}

	if ( 'createTextRange' in node ) {
		range = document.selection.createRange();
		if ( range.parentElement() == node ) {
			dup = range.duplicate();
			if ( node.type === 'text' ) {
				node.focus();
				start = -dup.moveStart('character', -node.value.length);
				end = start + range.text.length;
			} else {
				// textarea
				regexp = /\r/g;
				dup.moveToElementText(node);
				dup.setEndPoint('EndToStart', range);
				start = dup.text.replace(regexp, '').length;
				dup.setEndPoint('EndToEnd', range);
				end = dup.text.replace(regexp, '').length;
				dup = document.selection.createRange();
				dup.moveToElementText(node);
				dup.moveStart('character', start);
				while (dup.move('character', -dup.compareEndPoints('StartToStart', range))) {
					start += 1;
				}
				dup.moveStart('character', end - start);
				while (dup.move('character', -dup.compareEndPoints('StartToEnd', range))) {
					end += 1;
				}
			}
		}
	}

	return {
		start: start,
		end: end
	};
};

/**
 * Set selection for node
 * @param {jQuery/DOM} node jQuery or native DOM node
 * @param {number} start Selection start position
 * @param {number} end   Selection end position
 */
LJ.DOM.setSelection = function (node, start, end) {
	var range;
	if (!node.nodeName) {
		node = node.get(0);
	}
	// see https://bugzilla.mozilla.org/show_bug.cgi?id=265159
	node.focus();
	if( node.setSelectionRange ){
		node.setSelectionRange(start, end);
	}
	// IE, "else" for opera 10
	else if (document.selection && document.selection.createRange){
		range = node.createTextRange();
		range.collapse(true);
		range.moveEnd('character', end);
		range.moveStart('character', start);
		range.select();
	}
};

/**
 * Set cursor position inside of input/textarea element
 * @param {jQuery/DOM} node     jQuery or DOM node
 * @param {[type]} position Cursor position
 */
LJ.DOM.setCursor = function (node, position) {
	var text, length, absPosition;
	if (!node.nodeName) {
		node = node.get(0);
	}

	text = ( 'value' in node ? node.value : node.text ).replace(/\r/, ''),
	length = text.length;

	// convenient positions
	if (position === 'end') {
		return LJ.DOM.setSelection(node, length, length);
	}
	if (position === 'start') {
		return LJ.DOM.setSelection(node, 0, 0);
	}
	// calculation of correct caret position
	if (position > 0) {
		if (position > length) {
			position = length;
		}
	} else if (position !== 0) {
		absPosition = Math.abs(position);
		position = absPosition > length ? 0 : length - absPosition;
	}
	LJ.DOM.setSelection(node, position, position);
};

/**
 * @namespace LJ.UI Namespace should contain utility functions that are connected with widgets.
 */
LJ.UI = LJ.UI || {};

LJ.UI._mixins = {};

/**
 * Register a mixin to allow to use it later in the jQuery UI widgets.
 *
 * @param {string} name Name of the widget.
 * @param {Function} module The function that will bootsrap widget. The Function will be applied
 *     to the widget instance and the return object will represent the public api for the mixin.
 */
LJ.UI.mixin = function(name, module) {
	if (arguments.length === 1) {
		if (LJ.UI._mixins.hasOwnProperty(name)) {
			return LJ.UI._mixins[name];
		} else {
			LJ.console.log('Warn: Mixin ', name, ' was called but is not defined yet.');
		}
	} else {
		LJ.UI._mixins[name] = module;
	}
};

(function() {

	var locale = (LJ.pageVar('locale', true) || 'en_LJ').substr(0, 2),
		//All handlers were directly copied from LJ::Lang code
		handlers = {
			be: plural_form_ru,
			en: plural_form_en,
			fr: plural_form_fr,
			hu: plural_form_singular,
			is: plural_form_is,
			ja: plural_form_singular,
			lt: plural_form_lt,
			lv: plural_form_lv,
			pl: plural_form_pl,
			pt: plural_form_fr,
			ru: plural_form_ru,
			tr: plural_form_singular,
			uk: plural_form_ru
		};

// English, Danish, German, Norwegian, Swedish, Estonian, Finnish, Greek,
// Hebrew, Italian, Spanish, Esperanto
function plural_form_en(count) {
	if (count == 1) {
		return 0;
	}

	return 1;
}

// French, Portugese, Brazilian Portuguese
function plural_form_fr(count) {
	if (count > 1) {
		return 1;
	}

	return 0;
}

// Croatian, Czech, Russian, Slovak, Ukrainian, Belarusian
function plural_form_ru(count) {
	if (typeof count === 'undefined') { return 0; }

	if (count % 10 == 1 && count % 100 != 11) {
		return 0;
	}

	if ((count % 10 >= 2 && count % 10 <= 4) &&
		(count % 100 < 10 || count % 100 >= 20)) {
		return 1;
	}

	return 2;
}

// Polish
function plural_form_pl(count) {
	if (count === 1) {
		return 0;
	}

	if ((count % 10 >= 2 && count % 10 <= 4) &&
		(count % 100 < 10 || count % 100 >= 20)) {
		return 1;
	}

	return 2;
}

// Lithuanian
function plural_form_lt(count) {
	if (count % 10 == 1 && count % 100 != 11) {
		return 0;
	}

	if ((count % 10 >= 2) &&
		(count % 100 < 10 || count % 100 >= 20)) {
		return 1;
	}

	return 2;
}

// Hungarian, Japanese, Korean (not supported), Turkish
function plural_form_singular(count) {
	return 0;
}

// Latvian
function plural_form_lv(count) {
	if (count % 10 === 1 && count % 100 !== 11) {
		return 0;
	}

	if (count != 0) {
		return 1;
	}

	return 2;
}

// Icelandic
function plural_form_is(count) {
	if (count % 10 === 1 && count % 100 !== 11) {
		return 0;
	}
	return 1;
}

	function pluralize(num, forms) {
		var handler = handlers.hasOwnProperty(locale) ? handlers[locale] : handlers['en'],
			form = handler(num);
		return forms[form] ? forms[form] : '';
	}

	/**
	 * Get localized string.
	 *
	 * @param {string} key A key to search.
	 * @param {Object} dict A hash to search values for substitution.
	 * @param {string=} def A default value to return if the string was not returned from the server.
	 *
	 * @return {string} Localized value for string.
	 */
	LJ.ml = function(key, dict, def) {
		var str = '', tmpl;
		dict = dict || {};

		if (Site.ml_text.hasOwnProperty(key)) {
			str = Site.ml_text[key];

			str = str.replace( /\[\[\?([\w-]+)\|(.*)\]\]/g, function(str, numstr, forms) {
				if (!dict.hasOwnProperty(numstr)) { return str; }

				var num = parseInt(dict[numstr], 10);
				return pluralize(num, forms.split('|'));
			});

			for (tmpl in dict) {
				if (dict.hasOwnProperty(tmpl)) {
					str = str.replace('%' + tmpl + '%', dict[tmpl]);
					str = str.replace('[[' + tmpl + ']]', dict[tmpl]);
				}
			}
		} else {
			str = def || '[' + key + ']';
			LJ.console.log("Text variable ["+ key +"] hasn't been defined.");
		}

		return str;
	};

}());

/**
 * @namespace LJ.Support The namespace should contain variables to check whether some funcionality is availible in the current browser.
 * If this part will become hige enough, we should switch to modernizr.
 * All fields should have the same names as in modernizr
 */
LJ.Support = LJ.Support || {};

LJ.Support.geoLocation = 'geolocation' in navigator;
//Incomplete implementation from modernizr
LJ.Support.touch = ('ontouchstart' in window) || window.DocumentTouch && document instanceof DocumentTouch;
LJ.Support.cors = window.XMLHttpRequest && 'withCredentials' in new XMLHttpRequest();
LJ.Support.history = !!window.history.pushState;


/* object extensions */
if (!Object.extend)
	Object.extend = function (d, s){
		if(d) for(var p in s) if(!d[p]) d[p] = s[p];
		return d;
	};

if (!Object.override)
	Object.override = function (d, s){
		if(d) for(var p in s) d[p] = s[p];
		return d;
	};

/* function extensions */
/**
 * Returns an array of all own enumerable properties found upon a given object,
 * in the same order as that provided by a for-in loop.
 *
 * @param {Object} The object whose enumerable own properties are to be returned.
 *
 * @return {Array} Array with properties names.
 */

Object.extend(Function.prototype, {
	bindEventListener: function(object) {
		var method = this; // Use double closure to work around IE 6 memory leak.
		return function(e) {
			e = Event.prep(e);
			return method.call(object, e);
		};
	}
});

// for back compatiblity with legacy code
// we can't rely on version === 9 because of browser/document mode
if (jQuery.browser.msie) {
	Function.prototype.bind = function(that) { // .length is 1
		var target = this,
			slice = [].slice;
		if (typeof target.apply != "function" || typeof target.call != "function")
			return new TypeError();

		var args = slice.call(arguments, 1); // for normal call
		var bound = function () {

			if (this instanceof bound) {

				var self = Object.create(target.prototype);
				var result = target.apply(
					self,
					args.concat(slice.call(arguments))
				);
				if (result !== null && Object(result) === result)
					return result;
				return self;

			} else {
				return target.apply(
					that,
					args.concat(slice.call(arguments))
				);

			}
		};

		return bound;
	}
}

Object.extend(Function, {
	defer: function(func, args/*, more than one*/) {
		args = Array.prototype.slice.call(arguments, 1);

		setTimeout(function() {
			func.apply(null, args);
		}, 0);
	},

	/**
	 * Create a function that will call a function func with arguments
	 * through setTimeout set to zero.
	 * @param {Function} func The function to wrap.
	 * @param {Object} args Any arguments to attach to function call.
	 *
	 * @return {Function} Return newly created delayed function.
	 */
	defered: function(func, args) {
		args = args || [];
		return function() {
			var args2 = args.concat([].slice.call(arguments, 0));

			Function.defer(func, args2);
		};
	}
});



/* class helpers */
indirectObjects = [];

Class = function(superClass){
	// Set the constructor:
	var constructor = function(){
		if(arguments.length)
			this.init.apply(this, arguments);
	};
	//   -- Accomplish static-inheritance:
	Object.override(constructor, Class);  // inherit static methods from Class

	superClass = superClass || function(){
	};
	superClassFunc = function(){
	};
	Object.extend(superClassFunc.prototype, superClass.prototype);
	Object.extend(superClassFunc.prototype, {
		init: function(){
		},
		destroy: function(){
		}
	});
	Object.override(constructor, superClass); // inherit static methods from the superClass
	constructor.superClass = superClassFunc.prototype;

	// Set the constructor's prototype (accomplish object-inheritance):
	constructor.prototype = new superClass();
	constructor.prototype.constructor = constructor; // rev. 0.7
	//   -- extend prototype with Class instance methods
	Object.extend(constructor.prototype, Class.prototype);
	//   -- override prototype with interface methods
	for(var i = 1; i < arguments.length; i++)
		Object.override(constructor.prototype, arguments[i]);

	return constructor;
};

Class.prototype = {
	destroy: function(){
		try{
			if(this.indirectIndex)
				indirectObjects[ this.indirectIndex ] = undefined;
			delete this.indirectIndex;
		} catch(e){
		}

		for(var property in this){
			try{
				delete this[ property ];
			} catch(e){
			}
		}
	}
};



/* string extensions */
Object.extend(String, {
	escapeJSChar: function( c ) {
		// try simple escaping
		switch( c ) {
			case "\\": return "\\\\";
			case "\"": return "\\\"";
			case "'":  return "\\'";
			case "\b": return "\\b";
			case "\f": return "\\f";
			case "\n": return "\\n";
			case "\r": return "\\r";
			case "\t": return "\\t";
		}

		// return raw bytes now ... should be UTF-8
		if( c >= " " )
			return c;

		// try \uXXXX escaping, but shouldn't make it for case 1, 2
		c = c.charCodeAt( 0 ).toString( 16 );
		switch( c.length ) {
			case 1: return "\\u000" + c;
			case 2: return "\\u00" + c;
			case 3: return "\\u0" + c;
			case 4: return "\\u" + c;
		}

		// should never make it here
		return "";
	},

	encodeEntity: function( c ) {
		switch( c ) {
			case "<": return "&lt;";
			case ">": return "&gt;";
			case "&": return "&amp;";
			case '"': return "&quot;";
			case "'": return "&apos;";
		}
		return c;
	},

	decodeEntity: function( c ) {
		switch( c ) {
			case "amp": return "&";
			case "quot": return '"';
			case "apos": return "'";
			case "gt": return ">";
			case "lt": return "<";
		}
		var m = c.match( /^#(\d+)$/ );
		if( m && defined( m[ 1 ] ) )
			return String.fromCharCode( m[ 1 ] );
		m = c.match( /^#x([0-9a-f]+)$/i );
		if(  m && defined( m[ 1 ] ) )
			return String.fromCharCode( parseInt( hex, m[ 1 ] ) );
		return c;
	}
});

Object.extend(String.prototype, {
	escapeJS: function()
	{
		return this.replace( /([^ -!#-\[\]-~])/g, function( m, c ) { return String.escapeJSChar( c ); } )
	},

	/**
	 * Encode a string to allow a secure insertion in html code.
	 */
	encodeHTML: function() {
		return this.replace( /([<>&\"\'])/g, function( m, c ) { return String.encodeEntity( c ) } ); /* fix syntax highlight: " */
	},

	decodeHTML: function() {
		return this.replace( /&(.*?);/g, function( m, c ) { return String.decodeEntity( c ) } );
	},

	/**
	 * Add chars in front of string until it gets the length required.
	 *
	 * @param {Number} length Required string length.
	 * @param {String} padChar A char to add in front of string.
	 *
	 * @return {String} A padded string.
	 */
	pad: function(length, padChar)
	{
		return ((new Array(length + 1))
			.join(padChar)
			+ this
		).slice(-length);
	},

	supplant: function(o)
	{
		return this.replace(/{([^{}]*)}/g,
			function (a, b) {
				var r = o[b];
				return typeof r === 'string' || typeof r === 'number' ? r : a;
			});
	}
});

// will be shimmed using es6-shim later
if (typeof String.prototype.startsWith !== 'function') {
	String.prototype.startsWith = function(start) {
		return this.slice(0, String(start).length) === start;
	}
}

/* extend array object */
Object.extend(Array.prototype, {
	/**
	 * Check if index fits in current array size and fix it otherwise.
	 *
	 * @param {Number} fromIndex Index to check.
	 * @param {Number} defaultIndex This value will be taken if fromIndex is not defined.
	 *
	 * @return {Number} Fixed index value.
	 */
	fitIndex: function(fromIndex, defaultIndex)
	{
		if (fromIndex !== undefined || fromIndex == null) {
			fromIndex = defaultIndex;
		} else if (fromIndex < 0) {
			fromIndex = this.length + fromIndex;
			if (fromIndex < 0) {
				fromIndex = 0;
			}
		} else if (fromIndex >= this.length) {
			fromIndex = this.length - 1;
		}
		return fromIndex;
	},

	/**
	 * The function takes its arguments and add the ones that are not already inside to the end.
	 *
	 * @return {Number} New length of the array.
	 */
	add: function(/* a1, a2, ... */)
	{
		for (var j, a = arguments, i = 0; i < a.length; i++ ) {
			j = this.indexOf(a[i]);
			if (j < 0) {
				this.push(arguments[i]);
			}
		}
		return this.length;
	},

	/*
	 * The function takes its arguments and removes them from the array, if they are inside
	 *
	 * @return {Number} New length of the array.
	 */
	remove: function(/* a1, a2, ... */)
	{
		for (var j, a = arguments, i = 0; i < a.length; i++ ) {
			j = this.indexOf(a[i]);
			if (j >= 0) {
				this.splice(j, 1);
			}
		}
		return this.length;
	}
});

/* ajax */
var XMLHttpRequest = XMLHttpRequest || window.ActiveXObject && function(){
	return new ActiveXObject('Msxml2.XMLHTTP');
};

//dom.js
/* DOM class */
DOM = {
	getElement: function(e){
		return (typeof e == "string" || typeof e == "number") ? document.getElementById(e) : e;
	},

	addEventListener: function(e, eventName, func, useCapture){
		if(e.addEventListener)
			e.addEventListener(eventName, func, useCapture); else if(e.attachEvent)
			e.attachEvent('on' + eventName, func); else
			e['on' + eventName] = func;
	},

	removeEventListener: function(e, eventName, func, useCapture){
		if(e.removeEventListener)
			e.removeEventListener(eventName, func, useCapture); else if(e.detachEvent)
			e.detachEvent('on' + eventName, func); else
			e['on' + eventName] = undefined;
	},

	/* style */
	getComputedStyle: function(node){
		if(node.currentStyle){
			return node.currentStyle;
		}
		var defaultView = node.ownerDocument.defaultView;
		if(defaultView && defaultView.getComputedStyle){
			return defaultView.getComputedStyle(node, null);
		}
	},

	// given a window (or defaulting to current window), returns
	// object with .x and .y of client's usable area
	getClientDimensions: function(w){
		if(!w)
			w = window;

		var d = {};

		// most browsers
		if(w.innerHeight){
			d.x = w.innerWidth;
			d.y = w.innerHeight;
			return d;
		}

		// IE6, strict
		var de = w.document.documentElement;
		if(de && de.clientHeight){
			d.x = de.clientWidth;
			d.y = de.clientHeight;
			return d;
		}

		// IE, misc
		if(document.body){
			d.x = document.body.clientWidth;
			d.y = document.body.clientHeight;
			return d;
		}

		return undefined;
	},

	getDimensions: function(e){
		if(!e)
			return undefined;

		var style = DOM.getComputedStyle(e);

		return {
			offsetLeft: e.offsetLeft,
			offsetTop: e.offsetTop,
			offsetWidth: e.offsetWidth,
			offsetHeight: e.offsetHeight,
			clientWidth: e.clientWidth,
			clientHeight: e.clientHeight,

			offsetRight: e.offsetLeft + e.offsetWidth,
			offsetBottom: e.offsetTop + e.offsetHeight,
			clientLeft: finiteInt(style.borderLeftWidth) + finiteInt(style.paddingLeft),
			clientTop: finiteInt(style.borderTopWidth) + finiteInt(style.paddingTop),
			clientRight: e.clientLeft + e.clientWidth,
			clientBottom: e.clientTop + e.clientHeight
		};
	},

	getAbsoluteDimensions: function(e){
		var d = DOM.getDimensions(e);
		if(!d)
			return d;
		d.absoluteLeft = d.offsetLeft;
		d.absoluteTop = d.offsetTop;
		d.absoluteRight = d.offsetRight;
		d.absoluteBottom = d.offsetBottom;
		var bork = 0;
		while(e){
			try{ // IE 6 sometimes gives an unwarranted error ("htmlfile: Unspecified error").
				e = e.offsetParent;
			} catch (err){
				if(++bork > 25)
					return null;
			}
			if(!e)
				return d;
			d.absoluteLeft += e.offsetLeft;
			d.absoluteTop += e.offsetTop;
			d.absoluteRight += e.offsetLeft;
			d.absoluteBottom += e.offsetTop;
		}
		return d;
	},


	setLeft: function(e, v){
		e.style.left = finiteInt(v) + "px";
	},
	setTop: function(e, v){
		e.style.top = finiteInt(v) + "px";
	},
	setWidth: function(e, v){
		e.style.width = Math.max(0, finiteInt(v)) + "px";
	},
	setHeight: function(e, v){
		e.style.height = Math.max(0, finiteInt(v)) + "px";
	},

	getWindowScroll: function(w){
		var s = {
			left: 0,
			top: 0
		};

		if(!w) w = window;
		var d = w.document;
		var de = d.documentElement;

		// most browsers
		if(w.pageXOffset !== undefined){
			s.left = w.pageXOffset;
			s.top = w.pageYOffset;
		}

		// ie
		else if(de && de.scrollLeft !== undefined){
			s.left = de.scrollLeft;
			s.top = de.scrollTop;
		}

		// safari
		else if(w.scrollX !== undefined){
			s.left = w.scrollX;
			s.top = w.scrollY;
		}

		// opera
		else if(d.body && d.body.scrollLeft !== undefined){
			s.left = d.body.scrollLeft;
			s.top = d.body.scrollTop;
		}

		return s;
	},

	getAbsoluteCursorPosition: function(event){
		event = event || window.event;
		var s = DOM.getWindowScroll(window);
		return {
			x: s.left + event.clientX,
			y: s.top + event.clientY
		};
	},

	/* dom methods */
	filterElementsByClassName: function(es, className){
		var filtered = [];
		for(var i = 0; i < es.length; i++){
			var e = es[ i ];
			if(DOM.hasClassName(e, className))
				filtered[ filtered.length ] = e;
		}
		return filtered;
	},

	filterElementsByAttribute: function(es, attr){
		if(!es)
			return [];
		if(!attr)
			return es;
		var filtered = [];
		for(var i = 0; i < es.length; i++){
			var element = es[ i ];
			if(!element)
				continue;
			if(element.getAttribute && ( element.getAttribute(attr) ))
				filtered[ filtered.length ] = element;
		}
		return filtered;
	},

	filterElementsByTagName: function(es, tagName){
		if(tagName == "*")
			return es;
		var filtered = [];
		tagName = tagName.toLowerCase();
		for(var i = 0; i < es.length; i++){
			var e = es[ i ];
			if(e.tagName && e.tagName.toLowerCase() == tagName)
				filtered[ filtered.length ] = e;
		}
		return filtered;
	},

	// private
	getElementsByTagAndAttribute: function(root, tagName, attr){
		if(!root)
			root = document;
		var es = root.getElementsByTagName(tagName);
		return DOM.filterElementsByAttribute(es, attr);
	},

	getElementsByAttributeAndValue: function(root, attr, value){
		var es = DOM.getElementsByTagAndAttribute(root, "*", attr);
		var filtered = [];
		for(var i = 0; i < es.length; i++)
			if(es[ i ].getAttribute(attr) == value)
				filtered.push(es[ i ]);
		return filtered;
	},

	getElementsByTagAndClassName: function(root, tagName, className){
		if(!root)
			root = document;
		var elements = root.getElementsByTagName(tagName);
		return DOM.filterElementsByClassName(elements, className);
	},

	getElementsByClassName: function(root, className){
		return DOM.getElementsByTagAndClassName(root, "*", className);
	},

	getAncestors: function(n, includeSelf){
		if(!n)
			return [];
		var as = includeSelf ? [ n ] : [];
		n = n.parentNode;
		while(n){
			as.push(n);
			n = n.parentNode;
		}
		return as;
	},

	getAncestorsByClassName: function(n, className, includeSelf){
		var es = DOM.getAncestors(n, includeSelf);
		return DOM.filterElementsByClassName(es, className);
	},

	getFirstAncestorByClassName: function(n, className, includeSelf){
		return DOM.getAncestorsByClassName(n, className, includeSelf)[ 0 ];
	},

	hasClassName: function(e, className){
		if(!e || !e.className)
			return false;
		var cs = e.className.split(/\s+/g);
		for(var i = 0; i < cs.length; i++){
			if(cs[ i ] == className)
				return true;
		}
		return false;
	},

	addClassName: function(e, className){
		if(!e || !className)
			return false;
		var cs = e.className.split(/\s+/g);
		for(var i = 0; i < cs.length; i++){
			if(cs[ i ] == className)
				return true;
		}
		cs.push(className);
		e.className = cs.join(" ");
		return false;
	},

	removeClassName: function(e, className){
		var r = false;
		if(!e || !e.className || !className)
			return r;
		var cs = (e.className && e.className.length) ? e.className.split(/\s+/g) : [];
		var ncs = [];
		for(var i = 0; i < cs.length; i++){
			if(cs[ i ] == className){
				r = true;
				continue;
			}
			ncs.push(cs[ i ]);
		}
		if(r)
			e.className = ncs.join(" ");
		return r;
	},

	// deprecated: use LJ.DOM.* instead
	getSelectedRange: LJ.DOM.getSelection,
	setSelectedRange: LJ.DOM.setSelection
};

$ = DOM.getElement;



//httpreq.js

// opts:
// url, onError, onData, method (GET or POST), data
// url: where to get/post to
// onError: callback on error
// onData: callback on data received
// method: HTTP method, GET by default
// data: what to send to the server (urlencoded)
HTTPReq = {
	getJSON: function(opts){
		var req = new XMLHttpRequest();

		var state_callback = function(){
			if(req.readyState != 4) return;

			if(req.status != 200){
				if(opts.onError) opts.onError(req.status ? "status: " + req.status : "no data");
				return;
			}

			var resObj;
			var e;
			try{
				eval("resObj = " + req.responseText + ";");
			} catch (e){
			}

			if(e || ! resObj){
				if(opts.onError)
					opts.onError("Error parsing response: \"" + req.responseText + "\"");

				return;
			}

			if(opts.onData)
				opts.onData(resObj);
		};

		req.onreadystatechange = state_callback;

		var method = opts.method || "GET";
		var data = opts.data || null;

		var url = opts.url;
		if(opts.method == "GET" && opts.data){
			url += url.match(/\?/) ? "&" : "?";
			url += opts.data
		}

		url += url.match(/\?/) ? "&" : "?";
		url += "_rand=" + Math.random();

		req.open(method, url, true);

		// we should send null unless we're in a POST
		var to_send = null;

		if(method.toUpperCase() == "POST"){
			req.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
			to_send = data;
		}

		req.send(to_send);
	},

	formEncoded: function(vars){
		var enc = [];
		var e;
		for(var key in vars){
			enc.push(encodeURIComponent(key) + "=" + encodeURIComponent(vars[key]));
		}
		return enc.join("&");
	}
};

/**
 * Object responsible for statistic integration
 * @param  {jQuery} $ jQuery
 * @return {Object}   Methods for statistic interation
 */
LJ.Stat = (function ($) {
	var selector = '#hello-world',	// block for statistic addition
		el = null;					// cached jquery element

	/**
	 * Adds counter via inserting image on the page
	 * @param {String} img Image url
	 */
	function addCounter( url ) {
		var img = $('<img />', {
			src: url,
			alt: 'lj-counter'
		});
		// cache selector
		el = el || $(selector);
		el.append(img);
	}

	return {
		addCounter: addCounter
	};
}(jQuery));

LJ.siteMessage = (function ($) {
	'use strict';

	var scheme = LJ.pageVar('scheme'),
		messageSelector = '.appwidget-sitemessages',
		selectors = {
			lanzelot: { selector: '#main_body', method: 'before' },
			horizon: { selector: '#big-content-wrapper', method: 'prepend' },
			lynx: { selector: 'body', method: 'prepend' },

			// for journal pages
			journal: { selector: '#lj_controlstrip_new', method: 'after' }
		},
		// placeholder for methods to return
		methods = null;

	// we should run code only when document is ready and only for user
	// that is not currently logged in
	$(function () {
		if (!Site.remoteUser) {
			// wait for API initialization (inside of livejournal.js)
			setTimeout(methods.get.bind(methods), 0);
		}
	});

	methods = {
		/**
		 * Retrieve message from server and show it
		 */
		get: function () {
			var that = this;

			LJ.Api.call('sitemessage.get_message', {}, function (content) {
				that.show(content);
			});
		},

		/**
		 * Show content as message
		 * @param  {String} content Html representation of the message
		 */
		show: function (content) {
			var type = selectors[ scheme ? scheme : 'journal' ];

			// we should do nothing for this scheme yet
			if (scheme === 'schemius') {
				return;
			}

			// remove existed messages
			$(messageSelector).remove();

			// add message on the page
			$(type.selector)[type.method](content);
		}
	};

	return methods;
}(jQuery));
