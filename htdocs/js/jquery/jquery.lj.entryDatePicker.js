/*!
 * LiveJournal datePicker for edit entries.
 *
 * Copyright 2011, dmitry.petrov@sup.com
 *
 * http://docs.jquery.com/UI
 * 
 * Depends:
 *	jquery.ui.core.js
 *	jquery.ui.widget.js
 *	jquery.lj.basicWidget.js
 *
 * @overview Widget represents a date picker on update.bml and editjournal.bml pages.
 *
 * Public API:
 * reset Return widget to the initial state
 * 
 */
(function($,window) {
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
				calendar: '.wrap-calendar',
				editLink: '#currentdate-edit',
				currentDate: '#currentdate-date'
			},
			//this input was located outside the widget markup
			customTimeFlag: jQuery()
		},

		_create: function() {
			var self = this;
			var states = this.options.states;

			this._totalStateClassNames = '';
			for (var i in states) if (states.hasOwnProperty(i)) {
				this._totalStateClassNames += ' ' + this.options.classNames[states[i]];
			}

			this._dateInputs = {};
			this.element.find(this.options.selectors.dateInputs).each(function() {
				if (this.name.length) {
					self._dateInputs[this.name] = jQuery(this);
				}
			});

			this._currentDate = this.element.find(this.options.selectors.currentDate);
			$.lj.basicWidget.prototype._create.apply(this);

			this._initialUpdateDate = this.options.updateDate;
			//if delayed posts are disabled we should get old bejavior
			this.options.disableOnEdit = !this.element.hasClass(this.options.classNames.delayed);
			this._updateTimer = null;
			this._bindControls();

			if (this.options.updateDate) {
				this._startTimer();
				this._setTime();
			}
		},

		/**
		 * Bind common events for the widget
		 */
		_bindControls: function() {
			var self = this;
			$.lj.basicWidget.prototype._bindControls.apply(this);
			//we do not need eny events in the old control

			this.element.find(this.options.selectors.editLink).click(function(ev) {
				self._setState('edit');
				ev.preventDefault();
			});
			if (this.options.disableOnEdit) { return; }

			var month = this._dateInputs.date_ymd_mm.val(),
				dateStr = this._dateInputs.date_ymd_yyyy.val() + "/" + month + "/"
						+ this._dateInputs.date_ymd_dd.val(),
				calendar = this.element.find(this.options.selectors.calendar);

			calendar.calendar({
				currentDate: new Date(dateStr),
				ml: {
					caption: Site.ml_text['entryform.choose_date'] || 'Choose date:'
				},
				endMonth: new Date(2037,11,31),
				showCellHovers: true
			}).bind("daySelected", function(ev, date) {
				var currentDate = calendar.calendar('option', 'currentDate');
				if( currentDate.getMonth() !== date.getMonth() ||
					currentDate.getDate() !== date.getDate() ||
					currentDate.getFullYear() !== date.getFullYear()) {
					self._setEditDate(date);
				}
			});

			var oldDate;

			jQuery()
				.add(this._dateInputs.min)
				.add(this._dateInputs.hour)
				.blur(function(ev) {
					var date = new Date(
						parseInt(self._dateInputs.date_ymd_yyyy.val(), 10),
						parseInt(self._dateInputs.date_ymd_mm.val(), 10) - 1,
						parseInt(self._dateInputs.date_ymd_dd.val(), 10),
						parseInt(self._dateInputs.hour.val(), 10),
						parseInt(self._dateInputs.min.val(), 10)
						);
					if (date - oldDate !== 0) {
						self._setEditDate(date)
					} else {
						self._startTimer();
					}
				}).focus(function(ev) {
					oldDate = new Date(
						parseInt(self._dateInputs.date_ymd_yyyy.val(), 10),
						parseInt(self._dateInputs.date_ymd_mm.val(), 10) - 1,
						parseInt(self._dateInputs.date_ymd_dd.val(), 10),
						parseInt(self._dateInputs.hour.val(), 10),
						parseInt(self._dateInputs.min.val(), 10)
						);
					if (self.options.state === 'future') {
						self._setState('infutureedit');
					} else {
						self._setState('inedit');
					}
				});
		},

		_setOption: function(name, value) {
			switch(name) {
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
			this._updateTimer = 0;
			if (completely) {
				this.options.updateDate = false;
				this.options.customTimeFlag.val('1');
			}
		},

		_startTimer: function() {
			var self = this;
			if (this.options.updateDate && !this._updateTimer) {
				this._updateTimer = setInterval(function() { self._setTime(); }, 1000);
			}
		},

		_setEditDate: function(date) {
			var current = new Date();
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
			state = state || 'default';

			this.element
				.removeClass(this._totalStateClassNames)
				.addClass(this.options.classNames[state]);

			switch(state) {
				case 'edit':
					if (this.options.disableOnEdit) {
						this._stopTimer(true);
					} else {
						this._startTimer();
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
					this.options.customTimeFlag.val('0');
					this._startTimer()
					break;
			};
			this.options.state = state;
		},

		reset: function() {
			this._setOption('state', 'default');
		},

		_setTime: function(time) {
			function twodigit(n){
				if (n < 10) {
					return "0" + n;
				} else {
					return n;
				}
			}

			var newTime = time || new Date();
			if (!newTime) {
				return false;
			}
			f = document.updateForm;
			if (!f) {
				return false;
			}

			this._dateInputs.date_ymd_yyyy.val(newTime.getFullYear() < 1900 ? newTime.getFullYear() + 1900 : newTime.getFullYear())
			this._dateInputs.date_ymd_mm.val(newTime.getMonth() + 1);
			this._dateInputs.date_ymd_dd.val(twodigit(newTime.getDate()));
			if (!time) {
				this._dateInputs.hour.val(twodigit(newTime.getHours()));
				this._dateInputs.min.val(twodigit(newTime.getMinutes()));
			}

			this._dateInputs.date_diff.val(1);

			var mNames = Site.ml_text['month.names.long'] ||
							["January", "February", "March", "April", "May", "June", "July",
							"August", "September", "October", "November", "December"];
			var cMonth = newTime.getMonth();
			var cDay = newTime.getDate();

			var monthLabel = mNames[cMonth];
			monthLabel = monthLabel.charAt(0).toUpperCase() + monthLabel.substr(1);
			var cYear = newTime.getFullYear() < 1900 ? newTime.getFullYear() + 1900 : newTime.getFullYear();
			this._currentDate.html(monthLabel + " " + cDay + ", " + cYear);

			return false;
		}
	});
}(jQuery, window));
