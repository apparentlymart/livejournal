 /**
 * @author dmitry.petrov@sup.com (Dmitry Petrov)
 * @fileoverview LiveJournal search box widget for s2 layers editor
 */

/**
 * @name $.lj.s2editSearchBox
 * @requires $.ui.core, $.ui.widget, $.lj.basicWidget
 * @class Widget represents search box on the top left corner of editor.
 *     For correct operation widget requires ace editor to be initialized.
 *
 */
(function($,window) {

	/** @lends $.lj.s2editSearchBox.prototype */
	$.widget('lj.s2editSearchBox.js', $.lj.basicWidget, {
		options: {
			classNames: {
				showResults: 'searchbox-done',
				preshow: 'searchbox-preshow',
				show: 'searchbox-show'
			},

			selectors: {
				input: '[name=search-input]',
				close: '.searchbox-close',
				prev: '.searchbox-prev',
				next: '.searchbox-next',
				gotoline: '.searchbox-info-gotoline',
				counter: '.searchbox-info-counter',
				current: '.searchbox-info-counter .current',
				total: '.searchbox-info-counter .total'
			}
		},

		// private methods
		_create: function() {
			$.lj.basicWidget.prototype._create.apply(this);
			this._searchWord = '';
			this._currentRange;

			this._visible = false;
			this._bindControls();
		},

		_getEditor: function() {
			return window.aceEditor && aceEditor.env.editor || null;
		},

		_bindControls: function() {
			var self = this;
			$.lj.basicWidget.prototype._bindControls.apply(this);

			this.element.bind('keydown', function(ev) {
				//handle esc
				if (ev.keyCode === 27) { self.hide(); }

				//handle (shift)-enter
				//if shift is pressed we search backwards
				if (ev.keyCode === 13) {
					ev.preventDefault();

					var word = self._el('input').val().trim(),
						backwards = ev.shiftKey === true,
						editor = self._getEditor();

					if (word.length === 0 || !editor) { return; }

					//ei try to go to the line, if ctrl is pressed
					if (ev.ctrlKey === true && word.match(/^\d+$/)) {
						editor.gotoLine(+word);
						return;
					}

					self.search(word, backwards);
				}
			});

			this._el('input')
				.labeledPlaceholder()
				.input(function(ev) {
					var val = this.value.trim();
					self.element.removeClass(self._cl('showResults'));
					self._el('gotoline').toggle(!/[^0-9]/.test(val) && val.length > 0);
				});

			this._input.input();

			var searchHandler = function(backwards, ev) {
				ev.preventDefault();
				self.search(self._searchWord, backwards);
			};

			this.element
				.on('click', this._s('close'), this.hide.bind(this))
				.on('click', this._s('next'), searchHandler.bind(this, false))
				.on('click', this._s('prev'), searchHandler.bind(this, true)); //prev direction
		},

		/**
		 * Search a text for a word.
		 *
		 * @param {string} word A word to search.
		 * @param {boolean} backwards Whether to search backwards
		 */
		search: function(word, backwards) {
			if (word.length === 0) { return; }

			var editor = this._getEditor(),
				options = {
					backwards: !!backwards,
					//search will be case sensitive if the words contains letters in uppercase
					caseSensitive: /[A-Z]/.test(word)
				};

			if (!editor) { return; }

			if (word !== this._searchWord) {
				editor.find(word, options);
				this._searchWord = word;
			} else {
				if (backwards) {
					editor.findPrevious();
				} else {
					editor.findNext();
				}
			}

			this._currentRange = editor.selection.getRange();
			this._updateSearchResultsCounter();
		},

		/**
		 * Update the the number of current highlighted word in search results.
		 */
		_updateSearchResultsCounter: function() {
			var editor = this._getEditor();

			if (!editor) { return; }

			var ranges = editor.$search.findAll(editor.getSession());
			if (!ranges || !ranges.length) {
				this._el('current').html(0);
				this._el('total').html(0);
				return;
			}

			var crtIdx = -1;
			var cur = this._currentRange;
			if (cur) {
				//compareRange function confuses array sort, so we replace
				//it with our own naive implementation
				ranges.sort(function(r1, r2) {
					return r1.start.row < r2.start.row ? -1 : 
									r1.start.row > r2.start.row ? 1 : 
										r1.start.column - r2.start.column;
				});

				var range;
				var start = cur.start;
				var end = cur.end;
				for (var i = 0, l = ranges.length; i < l; ++i) {
					range = ranges[i];
					if (range.isStart(start.row, start.column) && range.isEnd(end.row, end.column)) {
						crtIdx = i;
						break;
					}
				}
			}

			this.element.addClass(this._cl('showResults'));
			this._el('current').html(++crtIdx);
			this._el('total').html(ranges.length);
		},

		/**
		 * Show dialog.
		 */
		show: function() {
			if (!this._enabled) { return; }

			if (!this._visible) {
				this.element
					.addClass(this._cl('preshow'))
					.addClass(this._cl('show'));
			}

			this._el('input').focus().select();
			this._visible = true;
		},

		/**
		 * Hide dialog.
		 */
		hide: function() {
			this.element
					.removeClass(this._cl('preshow'))
					.removeClass(this._cl('show'));

			var editor = this._getEditor();
			if (editor) {
				editor.focus();
			}

			this._visible = false;
		},

		/**
		 * Enable the widget. Only enabled widget can be shown.
		 */
		enable: function() {
			this._enabled = true;

			$.lj.basicWidget.prototype.enable.apply(this);
		},

		/**
		 * Disable the widget.
		 */
		disable: function() {
			this._enabled = false;
			this.hide();
			$.lj.basicWidget.prototype.disable.apply(this);
		},

		/**
		 * Find element inside the widget and return it. Note, that function caches the elements
		 * and assigns them ti the widget object with the name _{name}
		 *
		 * @param {string} name Name of the selector to search in this.options.selectors
		 */
		_el: function(name) {
			var method = '_' + name;

			if (!this[method]) { this[method] = this.element.find(this.options.selectors[name]); };

			return this[method];
		},

		/**
		 * Fetch the class name from the options.
		 *
		 * @param {string} name Name of the class name to search in this.options.classNames.
		 */
		_cl: function(name) {
				return this.options.classNames[name];
		},

		/**
		 * Fetch the selector from the options.
		 *
		 * @param {string} name Name of the selector to search in this.options.selectors
		 */
		_s: function(name) {
				return this.options.selectors[name];
		}
	});

})(jQuery, window);


