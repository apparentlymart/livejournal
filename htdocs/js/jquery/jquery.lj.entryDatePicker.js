 /**
 * @author dmitry.petrov@sup.com (Dmitry Petrov)
 * @fileoverview LiveJournal post date widget for new post page.
 */

/**
 * @name $.lj.entryDatePicker
 * @requires $.ui.core, $.ui.widget, $.lj.basicWidget, $.lj.inlineCalendar, $.lj.calendar,
 *     $.dateentry(for old page), $.timeentry(for old page).
 * @class Widget allows to choose custom date for post and to revert it if necessary.
 */
(function($, window) {
	"use strict";

	var listeners = {
		onStartEdit: function(evt) {
			evt.data._setState('edit');
			evt.data._isCalendarOpen = true;
			evt.preventDefault();
		},

		onStopEdit: function(evt) {
			evt.data.reset();
			evt.data._isCalendarOpen = false;
			evt.preventDefault();
		},

		onChangeMonth: function(evt) {
			var self = evt.data,
				month = this.selectedIndex,
				newDate = self.currentDate;

			if (self._isEvent === false) {
				return;
			}

			newDate.setMonth(month);
			if(newDate.getMonth() !== month) {
				newDate = new Date(self.currentDate.getFullYear(), month + 1, 0, newDate.getHours(), newDate.getMinutes());
			}

			self._setEditDate(newDate);
		},

		onChangeTime: function(evt) {
			var self = evt.data || this,
				newDate, dateAr;
			
			if (self._isOldDesign)  {
				newDate = $(this).timeEntry('getTime');
			} else {
				dateAr = evt.target.value.split(':').map(function(el) { return parseInt(el, 10); });
				newDate = new Date();
				if (dateAr.length === 2) {
					if (dateAr[0] < 0) { dateAr[0] = 0; }
					if (dateAr[0] > 23) { dateAr[0] = 23; }
					if (dateAr[1] < 0) { dateAr[1] = 0; }
					if (dateAr[1] > 59) { dateAr[1] = 59; }

					newDate.setHours(dateAr[0]);
					newDate.setMinutes(dateAr[1]);
				}
			}

			if (self._isEvent === false) {
				return;
			}
			newDate.setFullYear(self.currentDate.getFullYear());
			newDate.setDate(self.currentDate.getDate());
			newDate.setMonth(self.currentDate.getMonth());
			self._setEditDate(newDate);
		},

		onChangeDate: function(evt) {
			var self = evt.data || this,
				newDate = (self._isOldDesign) ? $(this).dateEntry('getDate') :
												LJ.Util.Date.parse(evt.target.value);

			if (self._isEvent === false) {
				return;
			}
			newDate.setHours(self.currentDate.getHours());
			newDate.setMinutes(self.currentDate.getMinutes());
			self._setEditDate(newDate);
		}
	};

	/** @lends $.lj.entryDatePicker.prototype */
	$.widget('lj.entryDatePicker', jQuery.lj.basicWidget, {
		options: {
			state: 'default',
			//when the widget is in inedit or infutureedit states, the timers are paused.
			states: ['default', 'edit', 'inedit', 'infutureedit', 'future'],
			updateDate: true,
			//if true, widget sets custom_time flag if user clicks on edit link. Otherwise it
			//does so only on real time change from user.
			disableOnEdit: false,
			classNames: {
				'default': 'entrydate-date',
				'edit': 'entrydate-changeit',
				'inedit': 'entrydate-changeit',
				'infutureedit': 'entrydate-until',
				'future': 'entrydate-until',
				'delayed': 'entrydate-delayed'
			},
			selectors: {
				dateInputs: 'input, select',
				calendar: '.wrap-calendar .i-calendar',
				editLink: '#currentdate-edit',
				timezone: 'input[name=timezone]',
				monthSelect: '#_mm',
				dateString: '.entrydate-string'
			}
		},

		_create: function() {
			var self = this,
				states = this.options.states,
				state = states.length;

			this._totalStateClassNames = '';
			while (state) {
				this._totalStateClassNames += ' ' + this.options.classNames[states[--state]];
			}

			this._dateInputs = {};
			this.element.find(this.options.selectors.dateInputs).each(function() {
				if (this.name.length) {
					self._dateInputs[this.name] = jQuery(this);
				}
			});

			//In the old page we have three separate input fields for
			//the day, month and a year.
			this._isOldDesign = !!this._dateInputs.date_ymd_yyyy;
			this._dateString = this.element.find(this.options.selectors.dateString);

			$.lj.basicWidget.prototype._create.apply(this);

			this._initialUpdateDate = this.options.updateDate;

			if (!this._isOldDesign) {
				this._el('timezone').val(- (new Date()).getTimezoneOffset()/0.6);
			}

			if (this._initialUpdateDate) {
				this.currentDate = new Date();
				this._startTimer();
			} else {
				var inputs = this._dateInputs,
					timeParts = inputs.time.val().match(/([0-9]{1,2}):([0-9]{1,2})/);

				this.currentDate = null;
				if (this._isOldDesign) {
					this.currentDate = new Date(
						Number(inputs.date_ymd_yyyy.val()),
						Number(inputs.date_ymd_mm.val() - 1),
						Number(inputs.date_ymd_dd.val()),
						timeParts[1],
						timeParts[2]);
				} else {
					this.currentDate = LJ.Util.Date.parse(inputs.date.val());
					this.currentDate.setHours(timeParts[1]);
					this.currentDate.setMinutes(timeParts[2]);
				}
			}

			this._bindControls();
			this._setTime(this.currentDate);
		},

		/**
		 * Bind common events for the widget
		 */
		_bindControls: function() {
			var self = this;

			$.lj.basicWidget.prototype._bindControls.apply(this);
			//we do not need eny events in the old control

			this.element.find(this.options.selectors.editLink).bind('click', this, listeners.onStartEdit);
			this.element.find(this.options.selectors.backLink).bind('click', this, listeners.onStopEdit);

			$(this.options.selectors.monthSelect).bind('change', this, listeners.onChangeMonth);

			var calOptions = {
				currentDate: this.currentDate,
				dateFormat: LiveJournal.getLocalizedStr('date.format.short'),
				ml: {
					caption: LiveJournal.getLocalizedStr('entryform.choose_date', null, 'Choose date:')
				},
				endMonth: new Date(2037, 11, 31),
				showCellHovers: true
			};

			if (!this._isOldDesign) {
				$.extend(true, calOptions, {
					closeControl: false,
					bubbleClass: true,
					templates: {
						calendar: 'templates-Widgets-datepicker'
					},
					selectors: {
						prevMonth: '.cal-nav-prev',
						nextMonth: '.cal-nav-next',
						monthSelect: '.b-datepicker-controls-month',
						yearSelect: '.b-datepicker-controls-year'
					},
					classNames: {
						container: '',
						inactive : 'b-datepicker-calendar-day-disabled',
						future : 'b-datepicker-calendar-day-disabled',
						current  : 'b-datepicker-calendar-day-active'
					}
				});
			}

			this._el('calendar').calendar(calOptions)
				.bind('daySelected', function(evt, date) {
				var currentDate = $(this).calendar('option', 'currentDate');
				delete self._isCalendarOpen;
				self._isEvent = false; //we're not a blur event

				if (currentDate.getMonth() !== date.getMonth() || currentDate.getDate() !== date.getDate() || currentDate.getFullYear() !== date.getFullYear()) {
					date.setHours(currentDate.getHours());
					date.setMinutes(currentDate.getMinutes());
					self._setEditDate(date);
				}
			});

			if (this._isOldDesign) {
				//These aweful plugins are disabled on the new page.
				this._dateInputs.time.timeEntry({
					show24Hours: true,
					useMouseWheel: false,
					spinnerImage: ''
				}).bind('change', this, listeners.onChangeTime);

				this._dateInputs.date_ymd_yyyy.dateEntry({
					dateFormat: 'y ',
					useMouseWheel: false,
					spinnerImage: ''
				}).dateEntry('setDate', this.currentDate).bind('change', this, listeners.onChangeDate);

				this._dateInputs.date_ymd_dd.dateEntry({
					dateFormat: 'd ',
					useMouseWheel: false,
					spinnerImage: ''
				}).dateEntry('setDate', this.currentDate).bind('change', this, listeners.onChangeDate);
			} else {
				this._dateInputs.date.bind('blur', this, listeners.onChangeDate);
				this._dateInputs.time.bind('blur', this, listeners.onChangeTime);
			}
		},

		_setOption: function(name, value) {
			switch (name) {
				case 'state':
					this._setState(value);
					break;
				case 'updateDate':
					this.options.updateDate = value;
					break;
			}
		},

		_stopTimer: function(completely) {
			clearInterval(this._updateTimer);
			delete this._updateTimer;
			if (completely) {
				this.options.updateDate = false;
			}
		},

		/**
		 * Start a timer to update the page. Time should work only on the new post pages.
		 */
		_startTimer: function() {
			var self = this;
			if (this.options.updateDate && !this._updateTimer) {
				this._updateTimer = setInterval(function() {
					var current = new Date();
					current.setMilliseconds(self.currentDate.getMilliseconds());
					current.setSeconds(self.currentDate.getSeconds());

					if(+current > +self.currentDate){
						self._setTime();
					}
				}, 1000);
			}
		},

		/**
		 * Trigger change the date in the input fields on the page
		 *     and stop timer if necessary.
		 *
		 * @param {Date} date A date to set.
		 */
		_setEditDate: function(date) {
			if(this.options.state === 'default') {
				return;
			}

			var current = new Date(),
				toSet = new Date(date);
			current.setMilliseconds(0);
			current.setSeconds(0);
			current.setMinutes(0);
			current.setHours(0);
			toSet.setMilliseconds(0);
			toSet.setSeconds(0);
			toSet.setMinutes(0);
			toSet.setHours(0);

			var delta = +toSet - (+new Date());
			this._setTime(date);

			if (delta > 0) {
				this._setState('future');
			} else {
				this._setState('edit');
				this._stopTimer(true);
			}
		},

		_setState: function(state) {
			this.options.state = state = state || 'default';

			this.element
				.removeClass(this._totalStateClassNames)
				.addClass(this.options.classNames[state]);

			switch (state) {
				case 'edit':
					if (this.options.disableOnEdit) {
						this._stopTimer(true);
					} else {
						this._startTimer();
						this._dateInputs.custom_time.val(1);
					}
					break;
				case 'infutureedit':
				case 'inedit':
					this._stopTimer();
					break;
				case 'future':
					this._stopTimer(true);
					break;
				case 'default':
					this.options.updateDate = this._initialUpdateDate;
					this._dateInputs.custom_time.val(0);
					this._startTimer();
					break;
			}
		},

		/**
		 * Update all input fields with the date.
		 *
		 * @param {Date} date A date to set.
		 */
		_setTime: function(date) {
				var inputs = this._dateInputs;
				date = date || new Date();

				this._isEvent = false;
				if (this._isOldDesign) {
					inputs.date_ymd_yyyy.dateEntry('setDate', date);
					inputs.date_ymd_mm.val(date.getMonth() + 1);
					inputs.date_ymd_dd.dateEntry('setDate', date);
					inputs.time.timeEntry('setTime', date);
				} else {
					inputs.time.val(LJ.Util.Date.format(date, '%R'));
					inputs.date.val(LJ.Util.Date.format(date, 'short'));
				}

				if(!this._isCalendarOpen) {
					this._calendar.calendar('option', 'currentDate', date);
				}

				if (inputs.date_diff) {
					inputs.date_diff.val(1);
				}

				if(this.options.state === 'default') {
					this._dateString.text(LJ.Util.Date.format(date, 'long') + ', ' + LJ.Util.Date.format(date, '%R'));
				}

				delete this._isEvent;

				this.currentDate = date;

				return false;
		},

		/**
		 * Reset the widget to the initial state.
		 */
		reset: function() {
			this._setOption('state', 'default');
		}
	});
}(jQuery, window));
