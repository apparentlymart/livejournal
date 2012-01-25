/*!
 * LiveJournal datePicker for edit entries.
 *
 * Copyright 2011, dmitry.petrov@sup.com & vkurkin@sup.com
 *
 * http://docs.jquery.com/UI
 * 
 * Depends:
 *	jquery.ui.core.js
 *	jquery.ui.widget.js
 *	jquery.lj.basicWidget.js
 *	jquery.lj.inlineCalendar.js
 *	jquery.dateentry.js
 *	jquery.timeentry.js
 *
 * @overview Widget represents a date picker on update.bml and editjournal.bml pages.
 *
 * Public API:
 * reset Return widget to the initial state
 * 
 */
(function($, window) {
	var listeners = {
		onStartEdit: function(evt) {
			evt.data._setState('edit');
			evt.data._isCalendarOpen = true;
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
			if(newDate.getMonth() != month) {
				newDate = new Date(self.currentDate.getFullYear(), month + 1, 0, newDate.getHours(), newDate.getMinutes());
			}

			self._setEditDate(newDate);
		},
		onChangeTime: function(evt) {
			var newDate = $(this).timeEntry('getTime'),
				self = evt.data;

			if (self._isEvent === false) {
				return;
			}
			newDate.setFullYear(self.currentDate.getFullYear());
			newDate.setMonth(self.currentDate.getMonth());
			newDate.setDate(self.currentDate.getDate());
			self._setEditDate(newDate);
		},
		onChangeDate: function(evt) {
			var newDate = $(this).dateEntry('getDate'),
				self = evt.data;

			if (self._isEvent === false) {
				return;
			}
			newDate.setHours(self.currentDate.getHours());
			newDate.setMinutes(self.currentDate.getMinutes());
			self._setEditDate(newDate);
		}
	};

	$.widget('lj.entryDatePicker', jQuery.lj.basicWidget, {
		options: {
			state: 'default',
			//when the widget is in inedit or infutureedit states, the timers are paused.
			states: ['default', 'edit', 'inedit', 'infutureedit', 'future'],
			monthNames: Site.ml_text['month.names.long'] || ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
			updateDate: !Site.is_edit,
			//if true, widget sets custom_time flag if user clicks on edit link. Otherwise it
			//does so only on real time change from user.
			disableOnEdit: false,
			classNames: {
				'default': 'entrydate-date',
				'edit': 'entrydate-changeit',
				'inedit': 'entrydate-changeit',
				'infutureedit': 'entrydate-until',
				'future': Site.hasOwnProperty('is_delayed_post') && Site.is_delayed_post === 0 ? 'entrydate-changeit' : 'entrydate-until',
				'delayed': 'entrydate-delayed'
			},
			selectors: {
				dateInputs: 'input, select',
				calendar: '.wrap-calendar .i-calendar',
				editLink: '#currentdate-edit',
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

			this._dateString = this.element.find(this.options.selectors.dateString);

			$.lj.basicWidget.prototype._create.apply(this);

			if (this._initialUpdateDate = this.options.updateDate) {
				this.currentDate = new Date;
				this._startTimer();
			} else {
				var inputs = this._dateInputs,
					timeParts = inputs.time.val().match(/([0-9]{1,2}):([0-9]{1,2})/);

				this.currentDate = new Date(
					Number(inputs.date_ymd_yyyy.val()),
					Number(inputs.date_ymd_mm.val() - 1),
					Number(inputs.date_ymd_dd.val()),
					timeParts[1],
					timeParts[2]);
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

			$(this.options.selectors.monthSelect).bind('change', this, listeners.onChangeMonth);

			this._calendar = $(this.options.selectors.calendar, this.element).calendar({
				currentDate: this.currentDate,
				ml: {
					caption: Site.ml_text['entryform.choose_date'] || 'Choose date:'
				},
				endMonth: new Date(2037, 11, 31),
				showCellHovers: true
			}).bind('daySelected', function(evt, date) {
					var currentDate = $(this).calendar('option', 'currentDate');
					delete self._isCalendarOpen;

					if (currentDate.getMonth() !== date.getMonth() || currentDate.getDate() !== date.getDate() || currentDate.getFullYear() !== date.getFullYear()) {
						date.setHours(currentDate.getHours());
						date.setMinutes(currentDate.getMinutes());
						self._setEditDate(date);
					}
				});

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

		_startTimer: function() {
			var self = this;
			if (this.options.updateDate && !this._updateTimer) {
				this._updateTimer = setInterval(function() {
					var current = new Date;
					current.setMilliseconds(self.currentDate.getMilliseconds());
					current.setSeconds(self.currentDate.getSeconds());

					if(+current > +self.currentDate){
						self._setTime();
					}
				}, 1000);
			}
		},

		_setEditDate: function(date) {
			if(this.options.state == 'default') {
				return;
			}

			var current = new Date;
			current.setMilliseconds(0);
			current.setSeconds(0);
			date.setMilliseconds(0);
			date.setSeconds(0);

			var delta = +date - (+new Date);
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
					this._startTimer();
					break;
			}
		},

		reset: function() {
			this._setOption('state', 'default');
		},

		_setTime: (function(){
			function twodigit(n) {
				return n < 10 ? '0' + n : n;
			}

			return function(date) {
				var inputs = this._dateInputs;
				date = date || new Date;

				this._isEvent = false;
				inputs.date_ymd_yyyy.dateEntry('setDate', date);
				inputs.date_ymd_mm.val(date.getMonth() + 1);
				inputs.date_ymd_dd.dateEntry('setDate', date);
				inputs.time.timeEntry('setTime', date);

				if(!this._isCalendarOpen) {
					this._calendar.calendar('option', 'currentDate', date);
				}

				inputs.date_diff.val(1);

				if(this.options.state == 'default') {
					this._dateString.text(this.options.monthNames[date.getMonth()] + ' ' + date.getDate() + ', ' + date.getFullYear() + ', ' + twodigit(date.getHours()) + ':' + twodigit(date.getMinutes()));
				}

				delete this._isEvent;

				this.currentDate = date;

				return false;
			};
		})()
	});
}(jQuery, window));
