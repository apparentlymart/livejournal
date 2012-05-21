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
			secure = options.secure ? '; secure' : '';
		document.cookie = [name, '=', encodeURIComponent(value), expires, path, domain, secure].join('');
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
 * Add pub/sub functionality for an object.
 *
 * @param {Object} obj Target object.
 */
LJ.addPubSub = function(obj) {
	var o = jQuery({});

	obj.addEventListener = function() {
		o.on.apply(o, arguments);
	};

	obj.removeEventListener = function() {
		o.off.apply(o, arguments);
	};

	obj.dispatchMessage = function() {
		o.trigger.apply(o, arguments);
	};
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
	}
};

LJ.console = function() {
	var consoleExists = function() { return 'console' in window },
		runIfExists = function(method, args) {
			if (consoleExists() && console[method]) {
				console[method].apply(console, args);
				return true;
			}

			return false;
		};

	var consoleShim = {
		log: function() {
			if (jQuery.browser.msie && consoleExists()) {
				console.log( [].join.apply(arguments) );
			} else {
				runIfExists('log', arguments);
			}
		}
	};

	var timers = {};
	consoleShim.time = function(label) {
		if (!runIfExists('time', arguments) && !timers[label]) {
			timers[label] = +new Date();
		}
	}

	consoleShim.timeEnd = function(label) {
		if (!runIfExists('timeEnd', arguments) && timers[label]) {
			var now = +new Date();
			consoleShim.log(label + ': ' + (now - timers[label]) + 'ms');
			delete timers[label];
		}
	}

	return consoleShim;
}();

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

}

/**
 * Get the value of the constant.
 *
 * @param {string} name The name of the constant.
 * @return {*} The value of the constant or undefined if constant was not defined.
 */
LJ.getConst = function(name) {
	name = name.toUpperCase().replace(/\s+/g, '_');

	return (LJ._const.hasOwnProperty(name) ? LJ._const[name] : void 0);
}

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

LJ.define('LJ.Util.Date');

(function() {

	function normalizeFormat(format) {
		if (!format || format === 'short') {
			format = LiveJournal.getLocalizedStr('format.date.short');
		} else if (format === 'long') {
			format = LiveJournal.getLocalizedStr('format.date.long');
		}

		return format;
	}

	/**
	 * Parse date from string.
	 *
	 * @param {string} datestr The string containing the date.
	 * @param {string} format Required date string format.
	 */
	LJ.Util.Date.parse = function(datestr, format) {
		format = normalizeFormat(format);

		var testStr = normalizeFormat(format),
			positions = [ null ],
			pos = 0, token,
			regs = {
				'%y' : '(\\d{4})',
				'%m' : '(\\d{2})',
				'%d' : '(\\d{2})'
			};

		while( ( pos = testStr.indexOf( '%', pos ) ) !== -1 ) {
			token = testStr.substr( pos, 2 );
			if( token in regs ) {
				testStr = testStr.replace( token, regs[ token ] );
				positions.push( token );
			} else {
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
					// return ('' + date.getMonth()).pad(2, '0');
					return 'nostr';
				case 'D' :
					return ('' + date.getDate()).pad(2, '0');
				case 'Y' :
					return date.getFullYear();
				case 'R' :
					return ('' + date.getHours()).pad(2, '0') + ':' + ('' + date.getMinutes()).pad(2, '0');
				default:
					return str;
			}
		});
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
 * @namespace LJ.UI Namespace should contain utility functions that are connected with widgets.
 */
LJ.UI = LJ.UI || {};

/**
 * Private namespace to hold information about templates.
 */
LJ.UI._templates = {};

/**
 * Register new template in system.
 *
 * @param {string} name The name of the template.
 * @param {string} id Id of the script tag containing the templates or the template text.
 * @param {string=JQuery} type Type of the template. Default is jquery templates.
 */
LJ.UI.registerTemplate = function(name, id, type) {
	var node = jQuery('#' + id),
		template;

	type = type || 'JQuery';

	if (node.length > 0) {
		//jQuery.text() method returns empty string in IE8
		template = node.html();
	} else {
		template = id;
	}

	LJ.UI._templates[name] = {
		type: type
	}

	var tmplObject = LJ.UI._templates[name];

	switch(type) {
		case 'JQuery':
			jQuery.template(name, template);
			break;
	}

};

/**
 * Render the template with the data. Current version returns jQuery object
 *    but surely should be able to return rendered strings.
 *
 *  @param {string} name The name of the template. Template should be registered.
 *  @param {Object} data Data object to inset into template
 *
 *  @return {jQuery} jQuery object containing new markup.
 */
LJ.UI.template = function(name, data) {
	var tmplObj = LJ.UI._templates[name],
		html;

	if (!tmplObj) {
		LJ.console.log('Warn: template ', name, ' was called but is not defined yet.'); 
		return jQuery();
	}

	switch (tmplObj.type) {
		default:
			html = jQuery.tmpl(name, data);
	}

	return html;
};

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

/**
 * @namespace LJ.Support The namespace should contain variables to check whether some funcionality is availible in the current browser.
 * If this part will become hige enough, we should switch to modernizr.
 * All fields should have the same names as in modernizr
 */
LJ.Support = LJ.Support || {};

LJ.Support.geoLocation = 'geolocation' in navigator;
//Incomplete implementation from modernizr
LJ.Support.touch = ('ontouchstart' in window) || window.DocumentTouch && document instanceof DocumentTouch;
LJ.Support.cors = window.XMLHttpRequest && 'withCredentials' in new XMLHttpRequest() || 'XDomainRequest' in window;


/* object extensions */
if (!Object.extend)
	Object.extend = function (d, s){
		if(d) for(var p in s) if(!d[p]) d[p] = s[p];
		return d
	};

if (!Object.override)
	Object.override = function (d, s){
		if(d) for(var p in s) d[p] = s[p];
		return d
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
Object.extend(Object, {
	keys: function(o) {
		if (o !== Object(o)) {
			throw new TypeError('Object.keys called on non-object');
		}
		var ret=[],p;
		for(p in o) if(Object.prototype.hasOwnProperty.call(o,p)) ret.push(p);
		return ret;
	}
});


Object.extend(Function.prototype, {
	bind: function(that) { // .length is 1
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
		}

		return bound;
	},
	
	bindEventListener: function(object) {
		var method = this; // Use double closure to work around IE 6 memory leak.
		return function(e) {
			e = Event.prep(e);
			return method.call(object, e);
		};
	}
});

Object.extend(Function, {
	defer: function(func, args/*, more than one*/) {
		var args = [].slice.call(arguments, 1);

		setTimeout(function() {
			func.apply(null, args);
		}, 0);
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
	}
	Object.extend(superClassFunc.prototype, superClass.prototype)
	Object.extend(superClassFunc.prototype, {
		init: function(){
		},
		destroy: function(){
		}
	})
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
		return this.replace( /([<>&"])/g, function( m, c ) { return String.encodeEntity( c ) } ); /* fix syntax highlight: " */
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

	trim: function()
	{
		return this.replace(/^\s+|\s+$/g, '');
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

Object.extend(Date, {
	/**
	 * Return timestamp number for current moment.
	 *
	 * @return {Number} A Timestamp.
	 */
	now: function() {
		return +new Date;
	}
});

Object.extend(Array, {
	/**
	 * Returns true if an object is an array, false if it is not.
	 *
	 * @param {Object} Argument to test.
	 *
	 * @return {Boolean} Test result.
	 */
	isArray: function(arg) {
		return Object.prototype.toString.call(arg) == '[object Array]';
	}
});

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
	},

	/* javascript 1.5 array methods */
	/* http://developer-test.mozilla.org/en/docs/Core_JavaScript_1.5_Reference:Objects:Array#Methods */
	/**
	 * Creates a new array with all elements that pass the test implemented by the provided function.
	 *
	 * @param {Function} fun Function to test each element of the array.
	 * @param {Function} thisp Object to use as this when executing callback.
	 *
	 * @param {Array} Filtered array.
	 */
	filter: function(fun/*, thisp*/)
	{
		var thisp = arguments[1] || null;
		if (typeof fun !== "function") {
			throw new TypeError("First argument is not callable");
		}

		for (var i = 0, len = this.length >>> 0, res = []; i < len; i++) {
			if (i in this) {
				var val = this[i]; // in case fun mutates this
				if (fun.call(thisp, val, i, this))
					res.push(val);
			}
		}
		
		return res;
	},
	
	/**
	 * Executes a provided function once per array element.
	 *
	 * @param {Function} fun Function to test each element of the array.
	 * @param {Function} thisp Object to use as this when executing callback.
	 *
	 * @return {Void}
	 */
	forEach: function(fun/*, thisp*/)
	{
		if (typeof fun !== "function") {
			throw new TypeError("First argument is not callable");
		}

		var thisp = arguments[1] || null;
		for (var i = 0, len = this.length >>> 0; i < len; i++) {
			if (i in this) {
				fun.call(thisp, this[i], i, this);
			}
		}
	},
	
	/**
	 * Returns the first index at which a given element can be found in the array,
	 * or -1 if it is not present.
	 *
	 * @param {Object} elt Element to locate in the array.
	 * @param {Number} from The index at which to begin the search. Defaults to 0, i.e.
	 *     the whole array will be searched. If the index is greater than or equal
	 *     to the length of the array, -1 is returned, i.e. the array will not be
	 *     searched. If negative, it is taken as the offset from the end of the array.
	 *     Note that even when the index is negative, the array is still searched
	 *     from front to back. If the calculated index is less than 0, the whole
	 *     array will be searched.
	 *
	 * @return {Number} Array index.
	 */
	indexOf: function(elt/*, from*/)
	{
		if (this === null || this === void 0) {
			throw new TypeError();
		}

		var len = this.length >>> 0;
		
		var from = Number(arguments[1]) || 0;
		from = from < 0
				? Math.ceil(from)
				: Math.floor(from);
		if (from < 0) {
			from += len;
		}
		for (; from < len; from++) {
			if (((from in this) || (len > from + 1 && this[from] === void 0)) && this[from] === elt) {
				return from;
			}
		}
		return -1;
	},
	
	/**
	 * Returns the last index at which a given element can be found in the array,
	 * or -1 if it is not present. The array is searched backwards, starting at fromIndex.
	 *
	 * @param {Object} elt Element to locate in the array.
	 * @param {Number=0} from The index at which to start searching backwards. Defaults to
	 *     the array's length, i.e. the whole array will be searched. If the index is
	 *     greater than or equal to the length of the array, the whole array will be
	 *     searched. If negative, it is taken as the offset from the end of the array.
	 *     Note that even when the index is negative, the array is still searched from
	 *     back to front. If the calculated index is less than 0, -1 is returned, i.e.
	 *     the array will not be searched. 
	 *
	 * @return {Number} Array index.
	 */
	lastIndexOf: function(elt/*, from*/)
	{
		var len = this.length >>> 0;
		if (len === 1) {
			return -1;
		}
		
		var from = Number(arguments[1]);

		if (arguments.length === 1) {
			from = len;
		} else {
			if (isNaN(from)) {
				if (arguments[1] === void 0) {
					from = 0;
				} else {
					from = -1;
				}
			} else {
				from = (from < 0)
					? Math.ceil(from)
					: Math.floor(from);
				if (from < 0) {
					from += len;
				} else if (from >= len) {
					from = len - 1;
				}
			}
		}
		
		for (; from > -1; from--) {
			if (((from in this) || (len > from + 1 && this[from] === void 0)) && this[from] === elt) {
				return from;
			}
		}
		return -1;
	},

	/**
	 * Tests whether all elements in the array pass the test implemented by the provided function.
	 *
	 * Implementation from https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/every
	 *
	 * @param {Function} fun Function to test for each element.
	 * @param {Object=} thisp Object to use as this when executing fun.
	 *
	 * @return {Boolean} Test result.
	 */
	every: function(fun/*, thisp */) {
		if (this === void 0 || this === null) {
			throw new TypeError();
		}

		var t = Object(this);
		var len = t.length >>> 0;
		if (typeof fun !== "function") {
			throw new TypeError();
		}

		var thisp = arguments[1];
		for (var i = 0; i < len; i++) {
			if (i in t && !fun.call(thisp, t[i], i, t)) {
				return false;
			}
		}

		return true;
	},

	/**
	 * Tests whether some element in the array passes the test implemented
	 * by the provided function.
	 *
	 * Implementation from https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/some
	 *
	 * @param {Function} fun Function to test for each element.
	 * @param {Object=} thisp Object to use as this when executing fun.
	 *
	 * @return {Boolean} Test result.
	 */
	some: function(fun/*, thisp */) {
		if (this === void 0 || this === null) {
			throw new TypeError();
		}

		var t = Object(this);
		var len = t.length >>> 0;
		if (typeof fun !== "function") {
			throw new TypeError();
		}

		var thisp = arguments[1];
		for (var i = 0; i < len; i++) {
			if (i in t && fun.call(thisp, t[i], i, t)) {
				return true;
			}
		}

		return false;
	},

	/**
	 * Creates a new array with the results of calling a provided function on every element in this array.
	 *
	 * Implementation from https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/map
	 *
	 * @param {Function} callback Function that produces an element of the new Array from an element of the current one.
	 * @param {Object=} thisp Object to use as this when executing fun.
	 *
	 * @return {Boolean} New array.
	 */
	map: function(callback/*, thisp*/ ) {
		var A, k;
		var thisp = arguments[1] || null;

		if (this == null) {
			throw new TypeError(" this is null or not defined");
		}

		var O = Object(this);
		var len = O.length >>> 0;

		if ({}.toString.call(callback) != "[object Function]") {
			throw new TypeError(callback + " is not a function");
		}

		A = new Array(len);
		k = 0;
		while(k < len) {
			var kValue, mappedValue;

			if (k in O) {
				kValue = O[ k ];
				mappedValue = callback.call(thisp, kValue, k, O);
				A[ k ] = mappedValue;
			}
			k++;
		}

		return A;
	},

	/**
	 * Apply a function against an accumulator and each value of the array (from left-to-right)
	 * as to reduce it to a single value.
	 *
	 * Implementation from https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/Reduce
	 *
	 * @param {Function} accumulator Function to execute on each value in the array.
	 * @param {Object=} initial Object to use as the first argument to the first call of the callback.
	 *
	 * @return {Object} Result of function application.
	 */
	reduce: function(accumulator/*, initial */) {
		var i, l = Number(this.length), curr;
		
		if (typeof accumulator !== "function") { // ES5 : "If IsCallable(callbackfn) is false, throw a TypeError exception."
			throw new TypeError("First argument is not callable");
		}

		if (l === 0) {
			if (arguments.length > 1) {
				return arguments[1];
			} else {
				throw new TypeError("No initial value for empty array");
			}
		}

		if (l === null && (arguments.length <= 1)) {// == on purpose to test 0 and false.
			throw new TypeError("Array length is 0 and no second argument");
		}
		
		if (arguments.length <= 1) {
			curr = this[0]; // Increase i to start searching the secondly defined element in the array
			i = 1; // start accumulating at the second element
		} else {
			curr = arguments[1];
		}
		
		for (i = i || 0 ; i < l ; ++i) {
			if(i in this) {
				curr = accumulator.call(undefined, curr, this[i], i, this);
			}
		}
		
		return curr;
	},

	/**
	 * Apply a function simultaneously against two values of the array (from right-to-left)
	 * as to reduce it to a single value.
	 *
	 * @param {Function} callbackfn Function to execute on each value in the array.
	 * @param {Object=} initial Object to use as the first argument to the first call of the callback.
	 *
	 * @return {Object} Result of function application.
	 */
	reduceRight: function(callbackfn/*, initial */) {
		if (this === void 0 || this === null) {
			throw new TypeError();
		}

		var t = Object(this);
		var len = t.length >>> 0;
		if (typeof callbackfn !== "function") {
			throw new TypeError();
		}

		// no value to return if no initial value, empty array
		if (len === 0 && arguments.length === 1)
			throw new TypeError();

		var k = len - 1;
		var accumulator;
		if (arguments.length >= 2) {
			accumulator = arguments[1];
		} else {
			do {
				if (k in this) {
					accumulator = this[k--];
					break;
				}

				// if array contains no values, no initial value to return
				if (--k < 0) {
					throw new TypeError();
				}
			} while (true);
		}

		while (k >= 0) {
			if (k in t) {
				accumulator = callbackfn.call(undefined, accumulator, t[k], k, t);
			}
			k--;
		}

		return accumulator;
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
		}

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

	getSelectedRange: function(node){
		var start = 0,
			end = 0;
		if('selectionStart' in node){
			start = node.selectionStart;
			end = node.selectionEnd;
		} else if(node.createTextRange){
			var range = document.selection.createRange();
			if(range.parentElement() == node){
				var dup = range.duplicate();

				if(node.type == 'text'){
					node.focus();
					start = -dup.moveStart('character', -node.value.length);
					end = start + range.text.length;
				} else {// textarea
					var rex = /\r/g;
					dup.moveToElementText(node);
					dup.setEndPoint('EndToStart', range);
					start = dup.text.replace(rex, '').length;
					dup.setEndPoint('EndToEnd', range);
					end = dup.text.replace(rex, '').length;
					dup = document.selection.createRange();
					dup.moveToElementText(node);
					dup.moveStart('character', start);
					while(dup.move('character', -dup.compareEndPoints('StartToStart', range))){
						start++;
					}
					dup.moveStart('character', end - start);
					while(dup.move('character', -dup.compareEndPoints('StartToEnd', range))){
						end++;
					}
				}

			}
		}

		return {
			start: start,
			end: end
		}
	},

	setSelectedRange: function(node, start, end){
		// see https://bugzilla.mozilla.org/show_bug.cgi?id=265159
		node.focus();
		if(node.setSelectionRange){
			node.setSelectionRange(start, end);
		}
		// IE, "else" for opera 10
		else if(document.selection && document.selection.createRange){
			var range = node.createTextRange();
			range.collapse(true);
			range.moveEnd('character', end);
			range.moveStart('character', start);
			range.select();
		}
	}
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
