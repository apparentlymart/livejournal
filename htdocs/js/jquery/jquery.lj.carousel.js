/*!
 * LiveJournal widget Carousel for jQuery.
 *
 * Copyright 2011, vkurkin@sup.com
 *
 * http://docs.jquery.com/UI
 *
 * Depends:
 *	jquery.ui.core.js
 *	jquery.ui.widget.js
 *	jquery.lj.basicWidget.js
 *
 * Public API:
 * start Start the rotation
 * stop Stop the rotation
 */
(function($) {
	$.widget('lj.carousel', jQuery.lj.basicWidget, {
		options: {
			state: 'start',
			slideEffect: 'fade',
			enableSlideEvent: 'mouseout',
			disableSlideEvent: 'mouseover',
			delay: 3000,
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

		start: function() {
			this._setState('start');
		},

		stop: function() {
			this._setState('stop');
		},

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
				var options = this.options;

				this.element
					.delegate(options.selectors.caption, options.enableSlideEvent, this, onStartSlide)
					.delegate(options.selectors.caption, options.disableSlideEvent, this, onStopSlide);
			}
		})(),

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