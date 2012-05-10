/**
 * @fileOverview LiveJournal widget Carousel for jQuery.
 * @author <a href="mailto:b-vladi@cs-console.ru">Vlad Kurkin</a>
 */
(function($) {
	/**
	 *
	 * @class LiveJournal widget Carousel for jQuery.
	 * @name $.lj.carousel
	 * @requires $.ui.core, $.ui.widget, $.lj.basicWidget
	 * @extends $.lj.basicWidget
	 * @example
	 * <pre>
	 *	$('div.with-carousel-content')
	 *		.carousel()
	 *		.carousel('publicMethod')
	 *		.carousel({ many: options })
	 *		.carousel('option', 'getOptionName')
	 *		.carousel('option', 'setOptionName', 'setOptionValue')
	 *		.carousel('carouselhide', function( event ){}); // bind some event
	 *	</pre>
	 */
	$.widget('lj.carousel', jQuery.lj.basicWidget, {
		/** @lends $.lj.carousel.prototype */
		options: {
			state: 'start',
			slideEffect: 'fade',
			enableSlideEvent: 'mouseout',
			disableSlideEvent: 'mouseover',
			delay: 5000,
			currentIndex: 0,
			classNames: {
				activeContent: 'w-wave-up'
			},
			selectors: {
				item: 'li.w-wave',
				caption: 'div.w-wave-crest',
				content: 'div.w-wave-trough'
			}
		},

		/**
		 * Start carousel
		 */
		start: function() {
			this._setState('start');
		},


		/**
		 * Stop carousel
		 */
		stop: function() {
			this._setState('stop');
		},

		/**
		 * @private
		 */
		_create: function () {
			var self = this, selectors = this.options.selectors;

			this._animated = {};
			this._items = [];
			this._state = 'stop';
			this.element.find(selectors.item).each(function() {
				self._items.push({
					parent: $(this),
					caption: $(selectors.caption, this),
					content: $(selectors.content, this)
				});
			});

			var currentIndex = this.options.currentIndex;
			if (typeof currentIndex == 'number' && currentIndex > 0) {
				var numberItems = this._items.length - 1;
				if (currentIndex > numberItems) {
					currentIndex = numberItems;
				}
			} else {
				currentIndex = 0;
			}

			this._bindControls();
			this._setCurrentItem(currentIndex);
			this._setState(this.options.state);
		},

		/**
		 * @private
		 */
		_bindControls: (function () {
			function onStartSlide(evt) {
				evt.data._setState('start', evt);
			}

			function onStopSlide(evt) {
				var widget = evt.data;
				widget._setState('stop', evt);
				evt.data._setCurrentItem($(this).closest(widget.options.selectors.item).index());
			}

			return function () {
				var options = this.options,
					selectors = options.selectors,
					resultSelector = selectors.caption + ', ' + selectors.content;

				this.element
					.delegate(resultSelector, options.enableSlideEvent, this, onStartSlide)
					.delegate(resultSelector, options.disableSlideEvent, this, onStopSlide);
			}
		})(),

		/**
		 * @private
		 */
		_setCurrentItem: function (index) {
			var activeClass = this.options.classNames.activeContent, self = this;

			if (typeof index != 'number' || !(index in this._items)) {
				index = 0;
			}

			if (index == this.currentIndex) {
				return;
			}

			function onEndFade () {
				if (!--self._counter) {
					delete self._counter;
					self._state == 'start' && self._startSlider();
				}
			}

			if (this._currentItem) {
				this._counter = 2;
				this._currentItem.parent.removeClass(activeClass);

				if (this._state == 'start' && this.options.slideEffect == 'fade') {
					this._currentItem.content.fadeOut('slow', onEndFade);
				} else {
					this._currentItem.content.hide();
					onEndFade();
				}
			}

			this.currentIndex = index;
			this._currentItem = this._items[index];

			if(this._state == 'start' && this.options.slideEffect == 'fade') {
				this._currentItem.content.fadeIn('slow', onEndFade);
			} else {
				this._currentItem.content.show();
				onEndFade();
			}

			this._currentItem.parent.addClass(activeClass);
		},

		/**
		 * @private
		 */
		_setOption: function (name, value) {
			switch (name) {
				case 'currentIndex':
					if (typeof value == 'number' && value in this._items) {
						this.options.currentIndex = value;
						this._setCurrentItem(value);
					}
					break;
			}
		},

		/**
		 * @private
		 */
		_stopSlider: function () {
			this._timer = clearTimeout(this._timer);
		},

		_startSlider: function () {
			var self = this,
				delay = this.options.delay;

			this._stopSlider();
			this._timer = setTimeout(function () {
				self._setCurrentItem(self.currentIndex + 1);
			}, delay);
		},

		/**
		 * @private
		 */
		_setState: function (state) {
			switch (state) {
				case 'start':
					if (this._state == 'stop') {
						this._setCurrentItem(this.currentIndex);
						this._startSlider();
					}
					break;
				case 'stop':
					this._stopSlider();
					break;
			}

			this._state = state;
		}
	});
})(jQuery);