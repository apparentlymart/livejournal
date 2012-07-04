jQuery.noConflict();

jQuery.ajaxSetup({
	cache: false
});

jQuery.fn.ljAddContextualPopup = function(){
	if(!window.ContextualPopup) return this;

	return this.each(function(){
		ContextualPopup.searchAndAdd(this);
	});
};

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
	var $el = this.length > 1 ? this.first() : this;

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

jQuery.fn.hourglass = function(xhr){
	var hourglasses = [];
	this.each(function(){
		// is complete or was aborted
		if(xhr && (xhr.readyState == 0 || xhr.readyState == 4)) return;

		if(this.nodeType){ // node

		} else { // position from event
			var e = jQuery.event.fix(this),
				hourglass = new Hourglass(),
				offset = {};

			// from keyboard
			if(!e.clientX || !e.clientY){
				offset = jQuery(e.target).offset();
			}

			hourglass.init();
			hourglass.hourglass_at(offset.left || e.pageX, offset.top || e.pageY);
		}

		hourglasses.push(hourglass);

		if(xhr){
			jQuery(hourglass.ele).bind('ajaxComplete', function(event, request){
				if(request == xhr){
					hourglass.hide();
					jQuery(hourglass.ele).unbind('ajaxComplete', arguments.callee);
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
