/* http://keith-wood.name/dateEntry.html
 Date entry for jQuery v1.0.6.
 Written by Keith Wood (kbwood{at}iinet.com.au) March 2009.
 Dual licensed under the GPL (http://dev.jquery.com/browser/trunk/jquery/GPL-LICENSE.txt) and
 MIT (http://dev.jquery.com/browser/trunk/jquery/MIT-LICENSE.txt) licenses.
 Please attribute the author if you use it. */

/* Turn an input field into an entry point for a date value.
 The date can be entered via directly typing the value,
 via the arrow keys, or via spinner buttons.
 It is configurable to reorder the fields, to enforce a minimum
 and/or maximum date, and to change the spinner image.
 Attach it with $('input selector').dateEntry(); for default settings,
 or configure it with options like:
 $('input selector').dateEntry(
 {spinnerImage: 'spinnerSquare.png', spinnerSize: [20, 20, 0]}); */

(function($) { // Hide scope, no $ conflict

	/* DateEntry manager.
	 Use the singleton instance of this class, $.dateEntry, to interact with the date
	 entry functionality. Settings for fields are maintained in an instance object,
	 allowing multiple different settings on the same page. */
	function DateEntry() {
		this._disabledInputs = []; // List of date inputs that have been disabled
		this.regional = []; // Available regional settings, indexed by language code
		this.regional[''] = { // Default regional settings
			dateFormat: 'mdy/', // The format of the date text:
			// first three fields in order ('y' for year, 'Y' for two-digit year,
			// 'm' for month, 'n' for abbreviated month name, 'N' for full month name,
			// 'd' for day, 'w' for abbreviated day name and number,
			// 'W' for full day name and number), followed by separator(s) 
			monthNames: ['January', 'February', 'March', 'April', 'May', 'June',
				'July', 'August', 'September', 'October', 'November', 'December'], // Names of the months
			monthNamesShort: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
				'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], // Abbreviated names of the months
			dayNames: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
			// Names of the days
			dayNamesShort: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], // Abbreviated names of the days
			spinnerTexts: ['Today', 'Previous field', 'Next field', 'Increment', 'Decrement']
			// The popup texts for the spinner image areas
		};
		this._defaults = {
			appendText: '', // Display text following the input box, e.g. showing the format
			initialField: 0, // The field to highlight initially
			useMouseWheel: true, // True to use mouse wheel for increment/decrement if possible,
			// false to never use it
			defaultDate: null, // The date to use if none has been set, leave at null for now
			minDate: null, // The earliest selectable date, or null for no limit
			maxDate: null, // The latest selectable date, or null for no limit
			spinnerImage: 'spinnerDefault.png', // The URL of the images to use for the date spinner
			// Seven images packed horizontally for normal, each button pressed, and disabled
			spinnerSize: [20, 20, 8], // The width and height of the spinner image,
			// and size of centre button for current date
			spinnerBigImage: '', // The URL of the images to use for the expanded date spinner
			// Seven images packed horizontally for normal, each button pressed, and disabled
			spinnerBigSize: [40, 40, 16], // The width and height of the expanded spinner image,
			// and size of centre button for current date
			spinnerIncDecOnly: false, // True for increment/decrement buttons only, false for all
			spinnerRepeat: [500, 250], // Initial and subsequent waits in milliseconds
			// for repeats on the spinner buttons
			beforeShow: null, // Function that takes an input field and
			// returns a set of custom settings for the date entry
			altField: null, // Selector, element or jQuery object for an alternate field to keep synchronised
			altFormat: null // A separate format for the alternate field
		};
		$.extend(this._defaults, this.regional['']);
	}

	var PROP_NAME = 'dateEntry';

	$.extend(DateEntry.prototype, {
		/* Class name added to elements to indicate already configured with date entry. */
		markerClassName: 'hasDateEntry',

		/* Override the default settings for all instances of the date entry.
		 @param  options  (object) the new settings to use as defaults (anonymous object)
		 @return  (DateEntry) this object */
		setDefaults: function(options) {
			extendRemove(this._defaults, options || {});
			return this;
		},

		/* Attach the date entry handler to an input field.
		 @param  target   (element) the field to attach to
		 @param  options  (object) custom settings for this instance */
		_connectDateEntry: function(target, options) {
			var input = $(target);
			if (input.hasClass(this.markerClassName)) {
				return;
			}
			var inst = {};
			inst.options = $.extend({}, options);
			inst._selectedYear = 0; // The currently selected year
			inst._selectedMonth = 0; // The currently selected month
			inst._selectedDay = 0; // The currently selected day
			inst._field = 0; // The selected subfield
			inst.input = $(target); // The attached input field
			$.data(target, PROP_NAME, inst);
			var spinnerImage = this._get(inst, 'spinnerImage');
			var spinnerText = this._get(inst, 'spinnerText');
			var spinnerSize = this._get(inst, 'spinnerSize');
			var appendText = this._get(inst, 'appendText');
			var spinner = (!spinnerImage ? null : $('<span class="dateEntry_control" style="display: inline-block; ' + 'background: url(\'' + spinnerImage + '\') 0 0 no-repeat; ' + 'width: ' + spinnerSize[0] + 'px; height: ' + spinnerSize[1] + 'px;' + ($.browser.mozilla && $.browser.version < '1.9' ? // FF 2- (Win)
				' padding-left: ' + spinnerSize[0] + 'px; padding-bottom: ' + (spinnerSize[1] - 18) + 'px;' : '') + '"></span>'));
			input.wrap('<span class="dateEntry_wrap"></span>').after(appendText ? '<span class="dateEntry_append">' + appendText + '</span>' : '').after(spinner || '');
			input.addClass(this.markerClassName).bind('focus.dateEntry', this._doFocus).bind('blur.dateEntry', this._doBlur).bind('click.dateEntry', this._doClick).bind('keydown.dateEntry', this._doKeyDown).bind('keypress.dateEntry', this._doKeyPress);
			// Check pastes
			if ($.browser.mozilla) {
				input.bind('input.dateEntry', function(event) {
					$.dateEntry._parseDate(inst);
				});
			}
			if ($.browser.msie) {
				input.bind('paste.dateEntry', function(event) {
						setTimeout(function() {
							$.dateEntry._parseDate(inst);
						}, 1);
					});
			}
			// Allow mouse wheel usage
			if (this._get(inst, 'useMouseWheel') && $.fn.mousewheel) {
				input.mousewheel(this._doMouseWheel);
			}
			if (spinner) {
				spinner.mousedown(this._handleSpinner).mouseup(this._endSpinner).mouseover(this._expandSpinner).mouseout(this._endSpinner).mousemove(this._describeSpinner);
			}
		},

		/* Enable a date entry input and any associated spinner.
		 @param  input  (element) single input field */
		_enableDateEntry: function(input) {
			this._enableDisable(input, false);
		},

		/* Disable a date entry input and any associated spinner.
		 @param  input  (element) single input field */
		_disableDateEntry: function(input) {
			this._enableDisable(input, true);
		},

		/* Enable or disable a date entry input and any associated spinner.
		 @param  input    (element) single input field
		 @param  disable  (boolean) true to disable, false to enable */
		_enableDisable: function(input, disable) {
			var inst = $.data(input, PROP_NAME);
			if (!inst) {
				return;
			}
			input.disabled = disable;
			if (input.nextSibling && input.nextSibling.nodeName.toLowerCase() == 'span') {
				$.dateEntry._changeSpinner(inst, input.nextSibling, (disable ? 5 : -1));
			}
			$.dateEntry._disabledInputs = $.map($.dateEntry._disabledInputs, function(value) {
					return (value == input ? null : value);
				}); // Delete entry
			if (disable) {
				$.dateEntry._disabledInputs.push(input);
			}
		},

		/* Check whether an input field has been disabled.
		 @param  input  (element) input field to check
		 @return  (boolean) true if this field has been disabled, false if it is enabled */
		_isDisabledDateEntry: function(input) {
			return $.inArray(input, this._disabledInputs) > -1;
		},

		/* Reconfigure the settings for a date entry field.
		 @param  input  (element) input field to change
		 @param  name   (object) new settings to add or
		 (string) the option name
		 @param  value  (any, optional) the option value */
		_changeDateEntry: function(input, name, value) {
			var inst = $.data(input, PROP_NAME);
			if (inst) {
				var options = name;
				if (typeof name == 'string') {
					options = {};
					options[name] = value;
				}
				var currentDate = this._extractDate(inst.input.val(), inst);
				extendRemove(inst.options, options || {});
				if (currentDate) {
					this._setDate(inst, currentDate);
				}
			}
			$.data(input, PROP_NAME, inst);
		},

		/* Remove the date entry functionality from an input.
		 @param  input  (element) input field to affect */
		_destroyDateEntry: function(input) {
			$input = $(input);
			if (!$input.hasClass(this.markerClassName)) {
				return;
			}
			$input.removeClass(this.markerClassName).unbind('.dateEntry');
			if ($.fn.mousewheel) {
				$input.unmousewheel();
			}
			this._disabledInputs = $.map(this._disabledInputs, function(value) {
					return (value == input ? null : value);
				}); // Delete entry
			$input.parent().replaceWith($input);
			$.removeData(input, PROP_NAME);
		},

		/* Initialise the current date for a date entry input field.
		 @param  input  (element) input field to update
		 @param  date   (Date) the new date or null for now */
		_setDateDateEntry: function(input, date) {
			var inst = $.data(input, PROP_NAME);
			if (inst) {
				if (date === null || date === '') {
					inst.input.val('');
				} else {
					this._setDate(inst, date ? (typeof date == 'object' ? new Date(date.getTime()) : date) : null);
				}
			}
		},

		/* Retrieve the current date for a date entry input field.
		 @param  input  (element) input field to update
		 @return  (Date) current date or null if none */
		_getDateDateEntry: function(input) {
			var inst = $.data(input, PROP_NAME);
			return (inst ? this._extractDate(inst.input.val(), inst) : null);
		},

		/* Initialise date entry.
		 @param  target  (element) the input field or
		 (event) the focus event */
		_doFocus: function(target) {
			var input = (target.nodeName && target.nodeName.toLowerCase() == 'input' ? target : this);
			if ($.dateEntry._lastInput == input || $.dateEntry._isDisabledDateEntry(input)) {
				$.dateEntry._focussed = false;
				return;
			}
			var inst = $.data(input, PROP_NAME);
			$.dateEntry._focussed = true;
			$.dateEntry._lastInput = input;
			$.dateEntry._blurredInput = null;
			var beforeShow = $.dateEntry._get(inst, 'beforeShow');
			extendRemove(inst.options, (beforeShow ? beforeShow.apply(input, [input]) : {}));
			$.data(input, PROP_NAME, inst);
			$.dateEntry._parseDate(inst);
			setTimeout(function() {
				$.dateEntry._showField(inst);
			}, 10);
		},

		/* Note that the field has been exited.
		 @param  event  (event) the blur event */
		_doBlur: function(event) {
			$.dateEntry._blurredInput = $.dateEntry._lastInput;
			$.dateEntry._lastInput = null;
		},

		/* Select appropriate field portion on click, if already in the field.
		 @param  event  (event) the click event */
		_doClick: function(event) {
			var input = event.target;
			var inst = $.data(input, PROP_NAME);
			if (!$.dateEntry._focussed) {
				var dateFormat = $.dateEntry._get(inst, 'dateFormat');
				inst._field = 0;
				if (input.selectionStart != null) { // Use input select range
					var end = 0;
					for (var field = 0; field < 3; field++) {
						end += $.dateEntry._fieldLength(inst, field, dateFormat) + 1;
						inst._field = field;
						if (input.selectionStart < end) {
							break;
						}
					}
				} else if (input.createTextRange) { // Check against bounding boxes
					var src = $(event.srcElement);
					var range = input.createTextRange();
					var convert = function(value) {
						return {thin: 2, medium: 4, thick: 6}[value] || value;
					};
					var offsetX = event.clientX + document.documentElement.scrollLeft - (src.offset().left + parseInt(convert(src.css('border-left-width')), 10)) - range.offsetLeft; // Position - left edge - alignment
					var end = 0;
					for (var field = 0; field < 3; field++) {
						end += $.dateEntry._fieldLength(inst, field, dateFormat) + 1;
						range.collapse();
						range.moveEnd('character', end);
						inst._field = field;
						if (offsetX < range.boundingWidth) { // And compare
							break;
						}
					}
				}
			}
			$.data(input, PROP_NAME, inst);
			$.dateEntry._showField(inst);
			$.dateEntry._focussed = false;
		},

		/* Handle keystrokes in the field.
		 @param  event  (event) the keydown event
		 @return  (boolean) true to continue, false to stop processing */
		_doKeyDown: function(event) {
			if (event.keyCode >= 48) { // >= '0'
				return true;
			}
			var inst = $.data(event.target, PROP_NAME);
			switch (event.keyCode) {
				case 9:
					return (event.shiftKey ? // Move to previous date field, or out if at the beginning
						$.dateEntry._changeField(inst, -1, true) : // Move to next date field, or out if at the end
						$.dateEntry._changeField(inst, +1, true));
				case 35:
					if (event.ctrlKey) { // Clear date on ctrl+end
						$.dateEntry._setValue(inst, '');
					} else { // Last field on end
						inst._field = 2;
						$.dateEntry._adjustField(inst, 0);
					}
					break;
				case 36:
					if (event.ctrlKey) { // Current date on ctrl+home
						$.dateEntry._setDate(inst);
					} else { // First field on home
						inst._field = 0;
						$.dateEntry._adjustField(inst, 0);
					}
					break;
				case 37:
					$.dateEntry._changeField(inst, -1, false);
					break; // Previous field on left
				case 38:
					$.dateEntry._adjustField(inst, +1);
					break; // Increment date field on up
				case 39:
					$.dateEntry._changeField(inst, +1, false);
					break; // Next field on right
				case 40:
					$.dateEntry._adjustField(inst, -1);
					break; // Decrement date field on down
				case 46:
					$.dateEntry._setValue(inst, '');
					break; // Clear date on delete
			}
			return false;
		},

		/* Disallow unwanted characters.
		 @param  event  (event) the keypress event
		 @return  (boolean) true to continue, false to stop processing */
		_doKeyPress: function(event) {
			var chr = String.fromCharCode(event.charCode == undefined ? event.keyCode : event.charCode);
			if (chr < ' ') {
				return true;
			}
			var inst = $.data(event.target, PROP_NAME);
			$.dateEntry._handleKeyPress(inst, chr);
			return false;
		},

		/* Increment/decrement on mouse wheel activity.
		 @param  event  (event) the mouse wheel event
		 @param  delta  (number) the amount of change */
		_doMouseWheel: function(event, delta) {
			if ($.dateEntry._isDisabledDateEntry(event.target)) {
				return;
			}
			delta = ($.browser.opera ? -delta / Math.abs(delta) : ($.browser.safari ? delta / Math.abs(delta) : delta));
			var inst = $.data(event.target, PROP_NAME);
			inst.input.focus();
			if (!inst.input.val()) {
				$.dateEntry._parseDate(inst);
			}
			$.dateEntry._adjustField(inst, delta);
			event.preventDefault();
		},

		/* Expand the spinner, if possible, to make it easier to use.
		 @param  event  (event) the mouse over event */
		_expandSpinner: function(event) {
			var spinner = $.dateEntry._getSpinnerTarget(event);
			var inst = $.data($.dateEntry._getInput(spinner), PROP_NAME);
			if ($.dateEntry._isDisabledDateEntry(inst.input[0])) {
				return;
			}
			var spinnerBigImage = $.dateEntry._get(inst, 'spinnerBigImage');
			if (spinnerBigImage) {
				inst._expanded = true;
				var offset = $(spinner).offset();
				var relative = null;
				$(spinner).parents().each(function() {
					var parent = $(this);
					if (parent.css('position') == 'relative' || parent.css('position') == 'absolute') {
						relative = parent.offset();
					}
					return !relative;
				});
				var spinnerSize = $.dateEntry._get(inst, 'spinnerSize');
				var spinnerBigSize = $.dateEntry._get(inst, 'spinnerBigSize');
				$('<div class="dateEntry_expand" style="position: absolute; left: ' + (offset.left - (spinnerBigSize[0] - spinnerSize[0]) / 2 - (relative ? relative.left : 0)) + 'px; top: ' + (offset.top - (spinnerBigSize[1] - spinnerSize[1]) / 2 - (relative ? relative.top : 0)) + 'px; width: ' + spinnerBigSize[0] + 'px; height: ' + spinnerBigSize[1] + 'px; background: transparent url(' + spinnerBigImage + ') no-repeat 0px 0px; z-index: 10;"></div>').mousedown($.dateEntry._handleSpinner).mouseup($.dateEntry._endSpinner).mouseout($.dateEntry._endExpand).mousemove($.dateEntry._describeSpinner).insertAfter(spinner);
			}
		},

		/* Locate the actual input field from the spinner.
		 @param  spinner  (element) the current spinner
		 @return  (element) the corresponding input */
		_getInput: function(spinner) {
			return $(spinner).siblings('.' + $.dateEntry.markerClassName)[0];
		},

		/* Change the title based on position within the spinner.
		 @param  event  (event) the mouse move event */
		_describeSpinner: function(event) {
			var spinner = $.dateEntry._getSpinnerTarget(event);
			var inst = $.data($.dateEntry._getInput(spinner), PROP_NAME);
			spinner.title = $.dateEntry._get(inst, 'spinnerTexts')
				[$.dateEntry._getSpinnerRegion(inst, event)];
		},

		/* Handle a click on the spinner.
		 @param  event  (event) the mouse click event */
		_handleSpinner: function(event) {
			var spinner = $.dateEntry._getSpinnerTarget(event);
			var input = $.dateEntry._getInput(spinner);
			if ($.dateEntry._isDisabledDateEntry(input)) {
				return;
			}
			if (input == $.dateEntry._blurredInput) {
				$.dateEntry._lastInput = input;
				$.dateEntry._blurredInput = null;
			}
			var inst = $.data(input, PROP_NAME);
			$.dateEntry._doFocus(input);
			var region = $.dateEntry._getSpinnerRegion(inst, event);
			$.dateEntry._changeSpinner(inst, spinner, region);
			$.dateEntry._actionSpinner(inst, region);
			$.dateEntry._timer = null;
			$.dateEntry._handlingSpinner = true;
			var spinnerRepeat = $.dateEntry._get(inst, 'spinnerRepeat');
			if (region >= 3 && spinnerRepeat[0]) { // Repeat increment/decrement
				$.dateEntry._timer = setTimeout(function() {
						$.dateEntry._repeatSpinner(inst, region);
					}, spinnerRepeat[0]);
				$(spinner).one('mouseout', $.dateEntry._releaseSpinner).one('mouseup', $.dateEntry._releaseSpinner);
			}
		},

		/* Action a click on the spinner.
		 @param  inst    (object) the instance settings
		 @param  region  (number) the spinner "button" */
		_actionSpinner: function(inst, region) {
			if (!inst.input.val()) {
				$.dateEntry._parseDate(inst);
			}
			switch (region) {
				case 0:
					this._setDate(inst);
					break;
				case 1:
					this._changeField(inst, -1, false);
					break;
				case 2:
					this._changeField(inst, +1, false);
					break;
				case 3:
					this._adjustField(inst, +1);
					break;
				case 4:
					this._adjustField(inst, -1);
					break;
			}
		},

		/* Repeat a click on the spinner.
		 @param  inst    (object) the instance settings
		 @param  region  (number) the spinner "button" */
		_repeatSpinner: function(inst, region) {
			if (!$.dateEntry._timer) {
				return;
			}
			$.dateEntry._lastInput = $.dateEntry._blurredInput;
			this._actionSpinner(inst, region);
			this._timer = setTimeout(function() {
					$.dateEntry._repeatSpinner(inst, region);
				}, this._get(inst, 'spinnerRepeat')[1]);
		},

		/* Stop a spinner repeat.
		 @param  event  (event) the mouse event */
		_releaseSpinner: function(event) {
			clearTimeout($.dateEntry._timer);
			$.dateEntry._timer = null;
		},

		/* Tidy up after an expanded spinner.
		 @param  event  (event) the mouse event */
		_endExpand: function(event) {
			$.dateEntry._timer = null;
			var spinner = $.dateEntry._getSpinnerTarget(event);
			var input = $.dateEntry._getInput(spinner);
			var inst = $.data(input, PROP_NAME);
			$(spinner).remove();
			inst._expanded = false;
		},

		/* Tidy up after a spinner click.
		 @param  event  (event) the mouse event */
		_endSpinner: function(event) {
			$.dateEntry._timer = null;
			var spinner = $.dateEntry._getSpinnerTarget(event);
			var input = $.dateEntry._getInput(spinner);
			var inst = $.data(input, PROP_NAME);
			if (!$.dateEntry._isDisabledDateEntry(input)) {
				$.dateEntry._changeSpinner(inst, spinner, -1);
			}
			if ($.dateEntry._handlingSpinner) {
				$.dateEntry._lastInput = $.dateEntry._blurredInput;
			}
			if ($.dateEntry._lastInput && $.dateEntry._handlingSpinner) {
				$.dateEntry._showField(inst);
			}
			$.dateEntry._handlingSpinner = false;
		},

		/* Retrieve the spinner from the event.
		 @param  event  (event) the mouse click event
		 @return  (element) the target field */
		_getSpinnerTarget: function(event) {
			return event.target || event.srcElement;
		},

		/* Determine which "button" within the spinner was clicked.
		 @param  inst   (object) the instance settings
		 @param  event  (event) the mouse event
		 @return  (number) the spinner "button" number */
		_getSpinnerRegion: function(inst, event) {
			var spinner = this._getSpinnerTarget(event);
			var pos = ($.browser.opera || $.browser.safari ? $.dateEntry._findPos(spinner) : $(spinner).offset());
			var scrolled = ($.browser.safari ? $.dateEntry._findScroll(spinner) : [document.documentElement.scrollLeft || document.body.scrollLeft,
				document.documentElement.scrollTop || document.body.scrollTop]);
			var spinnerIncDecOnly = this._get(inst, 'spinnerIncDecOnly');
			var left = (spinnerIncDecOnly ? 99 : event.clientX + scrolled[0] - pos.left - ($.browser.msie ? 2 : 0));
			var top = event.clientY + scrolled[1] - pos.top - ($.browser.msie ? 2 : 0);
			var spinnerSize = this._get(inst, (inst._expanded ? 'spinnerBigSize' : 'spinnerSize'));
			var right = (spinnerIncDecOnly ? 99 : spinnerSize[0] - 1 - left);
			var bottom = spinnerSize[1] - 1 - top;
			if (spinnerSize[2] > 0 && Math.abs(left - right) <= spinnerSize[2] && Math.abs(top - bottom) <= spinnerSize[2]) {
				return 0; // Centre button
			}
			var min = Math.min(left, top, right, bottom);
			return (min == left ? 1 : (min == right ? 2 : (min == top ? 3 : 4))); // Nearest edge
		},

		/* Change the spinner image depending on button clicked.
		 @param  inst     (object) the instance settings
		 @param  spinner  (element) the spinner control
		 @param  region   (number) the spinner "button" */
		_changeSpinner: function(inst, spinner, region) {
			$(spinner).css('background-position', '-' + ((region + 1) * this._get(inst, (inst._expanded ? 'spinnerBigSize' : 'spinnerSize'))[0]) + 'px 0px');
		},

		/* Find an object's position on the screen.
		 @param  obj  (element) the control
		 @return  (object) position as .left and .top */
		_findPos: function(obj) {
			var curLeft = curTop = 0;
			if (obj.offsetParent) {
				curLeft = obj.offsetLeft;
				curTop = obj.offsetTop;
				while (obj = obj.offsetParent) {
					var origCurLeft = curLeft;
					curLeft += obj.offsetLeft;
					if (curLeft < 0) {
						curLeft = origCurLeft;
					}
					curTop += obj.offsetTop;
				}
			}
			return {left: curLeft, top: curTop};
		},

		/* Find an object's scroll offset on the screen.
		 @param  obj  (element) the control
		 @return  (number[]) offset as [left, top] */
		_findScroll: function(obj) {
			var isFixed = false;
			$(obj).parents().each(function() {
				isFixed |= $(this).css('position') == 'fixed';
			});
			if (isFixed) {
				return [0, 0];
			}
			var scrollLeft = obj.scrollLeft;
			var scrollTop = obj.scrollTop;
			while (obj = obj.parentNode) {
				scrollLeft += obj.scrollLeft || 0;
				scrollTop += obj.scrollTop || 0;
			}
			return [scrollLeft, scrollTop];
		},

		/* Get a setting value, defaulting if necessary.
		 @param  inst  (object) the instance settings
		 @param  name  (string) the setting name
		 @return  (any) the setting value */
		_get: function(inst, name) {
			return (inst.options[name] != null ? inst.options[name] : $.dateEntry._defaults[name]);
		},

		/* Extract the date value from the input field, or default to now.
		 @param  inst  (object) the instance settings */
		_parseDate: function(inst) {
			var currentDate = this._extractDate(inst.input.val(), inst) || this._normaliseDate(this._determineDate(this._get(inst, 'defaultDate'), inst) || new Date());
			inst._selectedYear = currentDate.getFullYear();
			inst._selectedMonth = currentDate.getMonth();
			inst._selectedDay = currentDate.getDate();
			inst._lastChr = '';
			inst._field = Math.max(0, Math.min(2, this._get(inst, 'initialField')));
			if (inst.input.val() != '') {
				this._showDate(inst);
			}
		},

		/* Extract the date value from a string.
		 @param  value  (string) the date text
		 @param  inst   (object) the instance settings
		 @return  (Date) the retrieved date or null if no value */
		_extractDate: function(value, inst) {
			var dateFormat = this._get(inst, 'dateFormat');
			var values = value.split(new RegExp('[\\' + dateFormat.substr(-1).split('').join('\\') + ']'));
			var year = inst._selectedYear;
			var month = inst._selectedMonth + 1;
			var day = inst._selectedDay;
			for (var i = 0, l = values.length; i < l; i++) {
				var num = parseInt(values[i], 10);
				num = (isNaN(num) ? 0 : num);
				var field = dateFormat.charAt(i);
				switch (field) {
					case 'y':
						year = num;
						break;
					case 'Y':
						year = (num % 100) + (new Date().getFullYear() - new Date().getFullYear() % 100);
						break;
					case 'm':
						month = num;
						break;
					case 'n':
					case 'N':
						month = $.inArray(values[i], this._get(inst, (field == 'N' ? 'monthNames' : 'monthNamesShort'))) + 1;
						break;
					case 'w':
					case 'W':
						if (dateFormat.charAt(3) == ' ') {
							values.splice(i, 1);
							num = parseInt(values[i], 10);
						} else {
							num = parseInt(values[i].substr(this._get(inst, (field == 'W' ? 'dayNames' : 'dayNamesShort'))[0].length + 1), 10);
						}
						num = (isNaN(num) ? 0 : num); // Fall through
					case 'd':
						day = num;
						break;
				}
			}

			return new Date(year, month - 1, day, 12);
		},

		/* Set the selected date into the input field.
		 @param  inst  (object) the instance settings */
		_showDate: function(inst) {
			this._setValue(inst, this._formatDate(inst, this._get(inst, 'dateFormat')));
			this._showField(inst);
		},

		/* Format a date as requested.
		 @param  inst    (object) the instance settings
		 @param  format  (string) the date format to use
		 @return  (string) the formatted date */
		_formatDate: function(inst, format) {
			var currentDate = '';
			for (var i = 0, l = format.length - 1; i < l; i++) {
				currentDate += (i == 0 ? '' : format.charAt(format.length - 1));
				var field = format.charAt(i);
				switch (field) {
					case 'y':
						currentDate += this._formatNumber(inst._selectedYear);
						break;
					case 'Y':
						currentDate += this._formatNumber(inst._selectedYear % 100);
						break;
					case 'm':
						currentDate += this._formatNumber(inst._selectedMonth + 1);
						break;
					case 'n':
					case 'N':
						currentDate += this._get(inst, (field == 'N' ? 'monthNames' : 'monthNamesShort'))[inst._selectedMonth];
						break;
					case 'd':
						currentDate += this._formatNumber(inst._selectedDay);
						break;
					case 'w':
					case 'W':
						currentDate += this._get(inst, (field == 'W' ? 'dayNames' : 'dayNamesShort'))[
							new Date(inst._selectedYear, inst._selectedMonth, inst._selectedDay, 12).getDay()] + ' ' + this._formatNumber(inst._selectedDay);
						break;
				}
			}
			return currentDate;
		},

		/* Highlight the current date field.
		 @param  inst  (object) the instance settings */
		_showField: function(inst) {
			var input = inst.input[0];
			if (inst.input.is(':hidden') || $.dateEntry._lastInput != input) {
				return;
			}
			var dateFormat = this._get(inst, 'dateFormat');
			var start = 0;
			for (var i = 0; i < inst._field; i++) {
				start += this._fieldLength(inst, i, dateFormat) + 1;
			}
			var end = start + this._fieldLength(inst, i, dateFormat);
			if (input.setSelectionRange) { // Mozilla
				input.setSelectionRange(start, end);
			} else if (input.createTextRange) { // IE
				var range = input.createTextRange();
				range.moveStart('character', start);
				range.moveEnd('character', end - inst.input.val().length);
				range.select();
			}
			if (!input.disabled) {
				input.focus();
			}
		},

		/* Calculate the field length.
		 @param  inst        (object) the instance settings
		 @param  field       (number) the field number (0-2)
		 @param  dateFormat  (string) the format for the date display
		 @return  (number) the length of this subfield */
		_fieldLength: function(inst, field, dateFormat) {
			field = dateFormat.charAt(field);
			switch (field) {
				case 'y':
					return 4;
				case 'n':
				case 'N':
					return this._get(inst, (field == 'N' ? 'monthNames' : 'monthNamesShort'))
						[inst._selectedMonth].length;
				case 'w':
				case 'W':
					return this._get(inst, (field == 'W' ? 'dayNames' : 'dayNamesShort'))
						[new Date(inst._selectedYear, inst._selectedMonth, inst._selectedDay, 12).getDay()].length + 3;
				default:
					return 2;
			}
		},

		/* Ensure displayed single number has a leading zero.
		 @param  value  (number) current value
		 @return  (string) number with at least two digits */
		_formatNumber: function(value) {
			return (value < 10 ? '0' : '') + value;
		},

		/* Update the input field and notify listeners.
		 @param  inst   (object) the instance settings
		 @param  value  (string) the new value */
		_setValue: function(inst, value) {
			if (value != inst.input.val()) {
				var altField = this._get(inst, 'altField');
				if (altField) {
					$(altField).val(!value ? '' : this._formatDate(inst, this._get(inst, 'altFormat') || this._get(inst, 'dateFormat')));
				}
				inst.input.val(value).trigger('change');
			}
		},

		/* Move to previous/next field, or out of field altogether if appropriate.
		 @param  inst     (object) the instance settings
		 @param  offset   (number) the direction of change (-1, +1)
		 @param  moveOut  (boolean) true if can move out of the field
		 @return  (boolean) true if exitting the field, false if not */
		_changeField: function(inst, offset, moveOut) {
			var atFirstLast = (inst.input.val() == '' || inst._field == (offset == -1 ? 0 : 2));
			if (!atFirstLast) {
				inst._field += offset;
			}
			this._showField(inst);
			inst._lastChr = '';
			$.data(inst.input[0], PROP_NAME, inst);
			return (atFirstLast && moveOut);
		},

		/* Update the current field in the direction indicated.
		 @param  inst    (object) the instance settings
		 @param  offset  (number) the amount to change by */
		_adjustField: function(inst, offset) {
			if (inst.input.val() == '') {
				offset = 0;
			}
			var field = this._get(inst, 'dateFormat').charAt(inst._field);
			var year = inst._selectedYear + (field == 'y' || field == 'Y' ? offset : 0);
			var month = inst._selectedMonth + (field == 'm' || field == 'n' || field == 'N' ? offset : 0);
			var day = (field == 'd' || field == 'w' || field == 'W' ? inst._selectedDay + offset : Math.min(inst._selectedDay, this._getDaysInMonth(year, month)));
			this._setDate(inst, new Date(year, month, day, 12));
		},

		/* Find the number of days in a given month.
		 @param  year   (number) the full year
		 @param  month  (number) the month (0 to 11)
		 @return  (number) the number of days in this month */
		_getDaysInMonth: function(year, month) {
			return new Date(year, month + 1, 0, 12).getDate();
		},

		/* Check against minimum/maximum and display date.
		 @param  inst  (object) the instance settings
		 @param  date  (Date) an actual date or
		 (number) offset in days from now or
		 (string) units and periods of offsets from now */
		_setDate: function(inst, date) {
			// Normalise to base time
			date = this._normaliseDate(this._determineDate(date || this._get(inst, 'defaultDate'), inst) || new Date());
			var minDate = this._normaliseDate(this._determineDate(this._get(inst, 'minDate'), inst));
			var maxDate = this._normaliseDate(this._determineDate(this._get(inst, 'maxDate'), inst));
			// Ensure it is within the bounds set
			date = (minDate && date < minDate ? minDate : (maxDate && date > maxDate ? maxDate : date));
			inst._selectedYear = date.getFullYear();
			inst._selectedMonth = date.getMonth();
			inst._selectedDay = date.getDate();
			this._showDate(inst);
			$.data(inst.input[0], PROP_NAME, inst);
		},

		/* A date may be specified as an exact value or a relative one.
		 @param  setting  (Date) an actual date or
		 (string) date in current format
		 (number) offset in days from now or
		 (string) units and periods of offsets from now
		 @param  inst     (object) the instance settings
		 @return  (Date) the calculated date */
		_determineDate: function(setting, inst) {
			var offsetNumeric = function(offset) { // E.g. +300, -2
				var date = $.dateEntry._normaliseDate(new Date());
				date.setDate(date.getDate() + offset);
				return date;
			};
			var offsetString = function(offset) { // E.g. '+2m', '-1w', '+3m +10d'
				var date = $.dateEntry._extractDate(offset, inst);
				if (date) {
					return date;
				}
				offset = offset.toLowerCase();
				date = $.dateEntry._normaliseDate(new Date());
				var year = date.getFullYear();
				var month = date.getMonth();
				var day = date.getDate();
				var pattern = /([+-]?[0-9]+)\s*(d|w|m|y)?/g;
				var matches = pattern.exec(offset);
				while (matches) {
					switch (matches[2] || 'd') {
						case 'd':
							day += parseInt(matches[1], 10);
							break;
						case 'w':
							day += parseInt(matches[1], 10) * 7;
							break;
						case 'm':
							month += parseInt(matches[1], 10);
							break;
						case 'y':
							year += parseInt(matches[1], 10);
							break;
					}
					matches = pattern.exec(offset);
				}
				return new Date(year, month, day, 12);
			};
			return (setting ? (typeof setting == 'string' ? offsetString(setting) : (typeof setting == 'number' ? offsetNumeric(setting) : setting)) : null);
		},

		/* Normalise date object to a common time.
		 @param  date  (Date) the original date
		 @return  (Date) the normalised date */
		_normaliseDate: function(date) {
			if (date) {
				date.setHours(12, 0, 0, 0);
			}
			return date;
		},

		/* Update date based on keystroke entered.
		 @param  inst  (object) the instance settings
		 @param  chr   (ch) the new character */
		_handleKeyPress: function(inst, chr) {
			var dateFormat = this._get(inst, 'dateFormat');
			if (dateFormat.substring(3).indexOf(chr) > -1) {
				this._changeField(inst, +1, false);
			} else if (chr >= '0' && chr <= '9') { // Allow direct entry of date
				var field = dateFormat.charAt(inst._field);
				var key = parseInt(chr, 10);
				var value = parseInt((inst._lastChr || '') + chr, 10);
				var year = (field != 'y' && field != 'Y' ? inst._selectedYear : value);
				var month = (field != 'm' && field != 'n' && field != 'N' ? inst._selectedMonth + 1 : (value >= 1 && value <= 12 ? value : (key > 0 ? key : inst._selectedMonth + 1)));
				var day = (field != 'd' && field != 'w' && field != 'W' ? inst._selectedDay : (value >= 1 && value <= this._getDaysInMonth(year, month - 1) ? value : (key > 0 ? key : inst._selectedDay)));
				this._setDate(inst, new Date(year, month - 1, day, 12));
				inst._lastChr = (field != 'y' ? '' : inst._lastChr.substr(Math.max(0, inst._lastChr.length - 2))) + chr;
			} else { // Allow text entry by month name
				var field = dateFormat.charAt(inst._field);
				if (field == 'n' || field == 'N') {
					inst._lastChr += chr.toLowerCase();
					var names = this._get(inst, (field == 'n' ? 'monthNamesShort' : 'monthNames'));
					var findMonth = function() {
						for (var i = 0; i < names.length; i++) {
							if (names[i].toLowerCase().substring(0, inst._lastChr.length) == inst._lastChr) {
								return i;
								break;
							}
						}
						return -1;
					};
					var month = findMonth();
					if (month == -1) {
						inst._lastChr = chr.toLowerCase();
						month = findMonth();
					}
					if (month == -1) {
						inst._lastChr = '';
					} else {
						var year = inst._selectedYear;
						var day = Math.min(inst._selectedDay, this._getDaysInMonth(year, month));
						this._setDate(inst, new Date(year, month, day, 12));
					}
				}
			}
		}
	});

	/* jQuery extend now ignores nulls!
	 @param  target  (object) the object to update
	 @param  props   (object) the new settings
	 @return  (object) the updated object */
	function extendRemove(target, props) {
		$.extend(target, props);
		for (var name in props) {
			if (props[name] == null) {
				target[name] = null;
			}
		}
		return target;
	}

	/* Attach the date entry functionality to a jQuery selection.
	 @param  command  (string) the command to run (optional, default 'attach')
	 @param  options  (object) the new settings to use for these countdown instances (optional)
	 @return  (jQuery) for chaining further calls */
	$.fn.dateEntry = function(options) {
		var otherArgs = Array.prototype.slice.call(arguments, 1);
		if (typeof options == 'string' && (options == 'isDisabled' || options == 'getDate')) {
			return $.dateEntry['_' + options + 'DateEntry'].apply($.dateEntry, [this[0]].concat(otherArgs));
		}
		return this.each(function() {
			var nodeName = this.nodeName.toLowerCase();
			if (nodeName == 'input') {
				if (typeof options == 'string') {
					$.dateEntry['_' + options + 'DateEntry'].apply($.dateEntry, [this].concat(otherArgs));
				} else {
					// Check for settings on the control itself
					var inlineSettings = ($.fn.metadata ? $(this).metadata() : {});
					$.dateEntry._connectDateEntry(this, $.extend(inlineSettings, options));
				}
			}
		});
	};

	/* Initialise the date entry functionality. */
	$.dateEntry = new DateEntry(); // Singleton instance

})(jQuery);
