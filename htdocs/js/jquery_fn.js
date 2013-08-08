//= require js/hourglass.js

/*global Hourglass */

jQuery.ajaxSetup({
	cache: false
});

/**
 * jQuery plugin that works with caret (it uses LJ.DOM.* methods and added for convenience only)
 * - if two arguments have been provided: setting selection from startPos to endPos
 * - if one argument: set cursor to startPos
 * - if no arguments: get selection of field
 *
 * @param  {number} startPos Start caret position
 * @param  {number} endPos   End caret position.
 */
jQuery.fn.caret = function (startPos, endPos) {
	var $el = this.length > 1 ? this.first() : this,
		length;

	if (startPos === 'start') {
		length = $el.val().length;
		LJ.DOM.setSelection($el, 0, 0);
		return this;
	}
	if (startPos === 'end') {
		length = $el.val().length;
		LJ.DOM.setSelection($el, length, length);
		return this;
	}

	if (typeof startPos === 'number') {
		if (typeof endPos !== 'number') {
			LJ.DOM.setCursor($el, startPos);
		} else {
			LJ.DOM.setSelection($el, startPos, endPos);
		}
		return this;
	} else {
		return LJ.DOM.getSelection($el);
	}
};


jQuery.fn.isCollapsed = function() {
	var selection = LJ.DOM.getSelection(this.get(0));
	return selection.start === selection.end;
};

/**
 * @deprecated Use hourglass.setEvent instead
 */
jQuery.fn.hourglass = function (xhr){
	var hourglasses = [];

	this.each(function () {
		var e,
			hourglass;

		// is complete or was aborted
		if (xhr && (xhr.readyState === 0 || xhr.readyState === 4)) {
			return;
		}

		if( !this.nodeType ) {
			// position from event
			e = jQuery.event.fix(this);
			hourglass = new Hourglass()
				.setEvent(e)
				.show();
		}

		hourglasses.push(hourglass);

		if (xhr) {
			hourglass.element.on('ajaxComplete', function (event, request){
				if (request === xhr){
					hourglass.remove();
				}
			});
		}
	});

	return hourglasses;
};

// not work for password
jQuery.fn.placeholder = (function()
{
	var check_focus = function() {
			if (this.value === this.getAttribute("placeholder")) {
				jQuery(this)
					.val("")
					.removeClass("placeholder");
			}
		},
		check_blur = function() {
			if (!this.value) {
				jQuery(this)
					.val(this.getAttribute("placeholder"))
					.addClass("placeholder");
			}
		},
		support;

	return function() {
		if (support === undefined) {
			support = "placeholder" in document.createElement("input");
		}
		if (support === true) {
			return this;
		} else {
			return this.each(function() {
				if (this.getAttribute("placeholder")) {
					var $this = jQuery(this);

					if (!$this.data('jQuery-has-placeholder')) {
						$this.focus(check_focus).blur(check_blur);

						jQuery(this.form)
							.submit(function() {
								$this.hasClass("placeholder") && $this.removeClass("placeholder").val("");
							});
					}

					this.value === this.getAttribute("placeholder") || !this.value
						? $this.val(this.getAttribute("placeholder")).addClass("placeholder")
						: $this.removeClass("placeholder");

					$this.data('jQuery-has-placeholder', true)
				}
			});
		}
	}
})();

//this one is fields type agnostic but creates additional label elements, which need to be styled
jQuery.fn.labeledPlaceholder = function(){
	function focus_action(input, label){
		label.hide();
	}

	function blur_action(input, label){
		if (input.val().length === 0) {
			label.show();
		}
	}

	return this.each(function(){

		if('placeholder' in document.createElement('input') && this.tagName.toLowerCase() === "input"){
			return;
		}
		if('placeholder' in document.createElement('textarea') && this.tagName.toLowerCase() === "textarea"){
			return;
		}

		var $this = jQuery(this),
			placeholder = $this.attr('placeholder');

		$this.wrap('<span class="placeholder-wrapper" />');

		if(!placeholder || placeholder.length === 0){
			return;
		}

		var label = jQuery("<label></label>").addClass('placeholder-label').mousedown(function(ev){
			setTimeout(function(){
				focus_action($this, label);
				$this.focus();
			}, 0);
		}).html(placeholder).insertBefore($this);
		$this.focus(function(){
			focus_action($this, label)
		}).blur(function(){
			blur_action($this, label)
		});

		blur_action($this, label);

	});
};

jQuery.fn.input = function(fn){
	return fn ? this.each(function(){
		var last_value = this.value;
		jQuery(this).bind("input keyup paste", function(e){
			// e.originalEvent use from trigger
			if(!e.originalEvent || this.value !== last_value){
				last_value = this.value;
				fn.apply(this, arguments);
			}
		})
	}) : this.trigger("input");
};

// ctrl+enter send form
jQuery.fn.disableEnterSubmit = function() {
	this.bind("keypress", function(e) {
		// keyCode == 10 in IE with ctrlKey
		if ((e.which === 13 || e.which === 10) && e.target && e.target.form) {
			if (e.ctrlKey && !jQuery(":submit", e.target.form).attr("disabled")
				&& (e.target.tagName === "TEXTAREA" || e.target.tagName === "INPUT")
			) {
				e.target.form.submit();
			}

			if (e.target.tagName === "INPUT") {
				e.preventDefault();
			}
		}
	});
	return this;
};

/* function based on markup:
	tab links: ul>li>a
	current tab: ul>li.current
	tab container: ul>li
	tab container current: ul>li.current
*/
(function ($) {
	var supportHistoryAPI = !!window.history.pushState;
	var dataHistory = {};

	function changeTab(containers, links, index) {
		links
			.parent()
			.removeClass('current')
			.eq(index)
			.addClass('current');

		containers.removeClass('current')
			.eq(index)
			.addClass('current');

		LiveJournal.run_hook('change_tab', index);
	}

	function onClick(evt) {
		var item = $(this).parent(),
			index = item.index(),
			data = evt.data;

		if (data.containers[index]) {
			changeTab(data.containers, data.links, index);

			if (supportHistoryAPI) {
				window.history.pushState(null, '', this.href);
			}

			evt.preventDefault();
		}
	}

	if (supportHistoryAPI) {
		$(window).bind('popstate', function () {
			var data = dataHistory[location.href];

			if (data && data.length) {
				var length = data.length;
				while (length) {
					var itemData = data[--length];
					changeTab(itemData.containers, itemData.links, itemData.index);
				}
			}
		});
	}

	$.fn.tabsChanger = function(container) {
		var links = this.children('li').children('a');

		if (container) {
			container = $(container);
		} else {
			// next sibling of links
			container = links.parent().parent().next();
		}

		container = container.children('li');

		if (supportHistoryAPI) {
			links.each(function (index) {
				var urlData = dataHistory[this.href];

				if (!urlData) {
					urlData = dataHistory[this.href] = [];
				}

				urlData.push({
					index: index,
					links: links,
					containers: container
				});
			});
		}

		links.bind('click', {
			containers: container,
			links: links
		}, onClick);

		return this;
	};

})(jQuery);

/** jQuery overlay plugin
 * After creation overlay visibility can be toggled with
 * $( '#selector' ).overlay( 'show' ) and $( '#selector' ).overlay( 'hide' )
 */
jQuery.fn.overlay = function(opts){
	var options = {
		hideOnInit: true,
		hideOnClick: true
	};

	function Overlay(layer, options){
		this.layer = jQuery(layer);
		this.options = options;
		this.updateState(this.options.hideOnInit);
		this.bindEvents();
	}

	Overlay.prototype.bindEvents = function(){
		var overlay = this;

		if(this.options.hideOnClick){
			overlay.layer.mousedown(function(ev){
				ev.stopPropagation();
			});

			jQuery(document).mousedown(function(ev){
				overlay.updateState(true);
				ev.stopPropagation();
			});
		}
	};

	Overlay.prototype.updateState = function(hide){
		this.layerVisible = !hide;
		if(this.layerVisible){
			this.layer.show();
		} else {
			this.layer.hide();
		}
	};

	Overlay.prototype.proccessCommand = function (cmd){
		switch(cmd){
			case 'show' :
				this.updateState(false);
				break;
			case 'hide' :
				this.updateState(true);
				break;
		}
	};

	var cmd;
	if(typeof opts === "string"){
		cmd = opts;
	}

	return this.each(function(){
		if(!this.overlay){
			var o = jQuery.extend({}, options, opts || {});
			this.overlay = new Overlay(this, o);
		}

		if(cmd.length > 0){
			this.overlay.proccessCommand(opts)
		}
	});
};

/**
 * Function assures that callback will run not faster then minDelay.
 *
 * @param {Function} callback A callback to run.
 * @param {Number} minDelay Minimum delay in ms.
 *
 * @return {Function} Callback wrapper to use as a collback in your code.
 */
jQuery.delayedCallback = function(callback, minDelay) {
	var callCount = 2,
		results,
		checkFinish = function() {
			callCount--;
			if (callCount === 0) {
				callback.apply(null, results);
			}
		}

	setTimeout(checkFinish, minDelay);
	return function() {
		results = [].slice.apply(arguments);
		checkFinish();
	};
};

/**
 * Fix behavior of select box: trigger change event on keyup
 */
jQuery.fn.selectFix = function () {
	'use strict';

	return this.filter('select').on('keyup', function (e) {
		var code = e.which;
		if (code >= 37 && code <= 40) {
			jQuery(this).trigger('change');
		}
	});
};

/**
 * Provide ability to check if element is on the screen
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 */
;(function ($) {
	'use strict';
	// cache window object
	var $win = $(window);
	$.expr[':'].screenable = function (element) {
		var win = {},
			el = {},
			$el = $(element);

			// window coordinates
			win.width = $win.width(),
			win.height = $win.height(),
			win.top = $win.scrollTop(),
			win.bottom = win.top + win.height,
			win.left = $win.scrollLeft(),
			win.right = win.left + win.width,

			// element coordinates
			el.width = $el.width();
			el.height = $el.height();
			el.top = $el.offset().top;
			el.bottom = el.top + el.height;
			el.left = $el.offset().left;
			el.right = el.left + el.width;

		return (el.bottom > win.top && el.top < win.bottom) && (el.right > win.left && el.left < win.right);
	};
}(jQuery));

/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Parse lj-likes plugin
 *              It parses all elements with class 'lj-like', uncomment their content
 *              and parse with LiveJournal.parseLikeButtons()
 * @todo Move plugin to separate file
 */
;(function ($) {
	'use strict';

	var
		/**
		 * Empty collection that will contain not parsed lj-like elements
		 * that are currently on the page
		 */
		_likes = $();

	/**
	 * Remove comments inside node and parse likes
	 * @param  {Object} node jQuery node
	 * @return {Object}      jQuery node
	 */
	function parse(node) {
		var html = node.html(),
			// regexp for removing _tmplitem attribute
			tmplRegexp = /_tmplitem=['"]\d+['"]/mig;

		// uncomment like buttons
		html = $.trim( html.replace(/<!--([\s\S]*?)-->/mig, '$1') );

		/**
		 * Clean _tmplitem attributes
		 *
		 * It's a quirk for jquery templates possible bug with commented nodes
		 * and double applying jquery templates.
		 * _tmplitem attributes are not removed after compilation.
		 * Fix for #LJSUP-14149
		 */
		if ( tmplRegexp.test(html) ) {
			html = html.replace(tmplRegexp, '');
		}

		LiveJournal.parseLikeButtons( node.html(html) );

		return node;
	}

	/**
	 * handler for scroll event for lazy loading of likes
	 */
	function lazyLoad() {
		var screenableLikes = null;

		if ( _likes.length === 0 ) {
			return;
		}

		// find likes that are on the screen
		screenableLikes = _likes.filter(':screenable');

		if ( !screenableLikes.length ) {
			return;
		}

		screenableLikes.each(function () {
			var node = $(this);

			// move parsing to the end of the event loop
			setTimeout(function () {
				parse( node );
			}, 0);
		});

		// remove handled likes from the queue
		_likes = _likes.not(screenableLikes);
	}

	// after document ready, cuz LiveJournal namespace is not defined yet
	$(function () {
		/**
		 * Handle scroll event.
		 * Notice: for mobile devices we don't threshold lazyLoad
		 * because it fires only at the end of scrolling (iOS)
		 */
		$(window).on('scroll', LJ.Support.touch ? lazyLoad : LJ.threshold(lazyLoad, 1000));
	});

	$.fn.ljLikes = function (opts) {
		var likes = null;

		if ( this.length === 0 ) {
			return this;
		}

		opts = $.extend({}, $.fn.ljLikes.defaults, opts || {});

		// find elements with lj-likes class
		likes = this.find('.lj-like')
			.add( this.filter('.lj-like') )
			// filter previously unused items only and mark them as used
			.filter(function () {
				if (this.used) {
					return false;
				}
				this.used = true;
				return true;
			});

		if (likes.length === 0) {
			return this;
		}

		if ( !opts.lazy ) {
			// not lazy: immediately parsing
			likes.each(function () {
				var node = $(this);

				// parse should be deferred
				setTimeout(function () {
					parse( node );
				}, 0);
			});
		} else {
			// add likes for further lazy loading
			_likes = _likes.add( likes );
			// parse all added screenable elements
			lazyLoad();
		}
		return this;
	};

	// default plugin options
	$.fn.ljLikes.defaults = {
		/**
		 * Lazy loading of likes - will be parsed when becomes screenable
		 * if false - we will parse likes at the moment
		 */
		lazy: true
	};
}(jQuery));
