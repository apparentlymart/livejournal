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
Object.extend(Function.prototype, {
	bind: function(object)
	{
		var method = this;
		return function() {
			return method.apply(object, arguments);
		}
	},
	
	bindEventListener: function(object) {
		var method = this; // Use double closure to work around IE 6 memory leak.
		return function(e) {
			e = Event.prep(e);
			return method.call(object, e);
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
	}
});

Object.extend(String.prototype, {
	escapeJS: function()
	{
		return this.replace( /([^ -!#-\[\]-~])/g, function( m, c ) { return String.escapeJSChar( c ); } )
	},
	
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
	}
});



/* extend array object */
Object.extend(Array.prototype, {
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

	add: function()
	{
		for (var j, a = arguments, i = 0; i < a.length; i++ ) {
			j = this.indexOf(a[i]);
			if (j < 0) {
				this.push(arguments[i]);
			}
		}
		return this.length;
	},

	remove: function()
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
	filter: function(fun, thisp)
	{
		for (var i = 0, len = this.length >>> 0, res = []; i < len; i++) {
			if (i in this) {
				var val = this[i]; // in case fun mutates this
				if (fun.call(thisp, val, i, this))
					res.push(val);
			}
		}
		
		return res;
	},
	
	forEach: function(fun, thisp)
	{
		for (var i = 0, len = this.length >>> 0; i < len; i++) {
			if (i in this) {
				fun.call(thisp, this[i], i, this);
			}
		}
	},
	
	indexOf: function(elt, from)
	{
		var len = this.length >>> 0;
		
		from = Number(from) || 0;
		from = from < 0
				? Math.ceil(from)
				: Math.floor(from);
		if (from < 0) {
			from += len;
		}
		for (; from < len; from++) {
			if (from in this && this[from] === elt)
				return from;
		}
		return -1;
	},
	
	lastIndexOf: function(elt, from)
	{
		var len = this.length >>> 0;
		
		var from = Number(from);
		if (isNaN(from)) {
			from = len - 1;
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
		
		for (; from > -1; from--) {
			if (from in this && this[from] === elt) {
				return from;
			}
		}
		return -1;
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
			var range = document.selection.createRange(),
				dup = range.duplicate();

			if(node.type == 'text'){
				start = -dup.moveStart('character', -100000);
				end = start + range.text.length;
			} else // textarea
			{
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

			// range.parentElement() drops selection in IE 7-8 in some cases.
			if(range.parentElement() != node){
				start = end = undefined;
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
			return;
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
