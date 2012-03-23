/**
 * @fileOverview LiveJournal widget Modal Window for jQuery.
 * @author <a href="mailto:b-vladi@cs-console.ru">Vlad Kurkin</a>
 */
(function ($, window) {
	/**
	 * @class LiveJournal widget Modal Window for jQuery.
	 * @name $.lj.modalWindow
	 * @requires $.ui.core, $.ui.widget
	 * @example
	 * <pre>
	 *	$('div.with-carousel-content')
	 *		.modalWindow()
	 *		.modalWindow('publicMethod')
	 *		.modalWindow({ many: options })
	 *		.modalWindow('option', 'getOptionName')
	 *		.modalWindow('option', 'setOptionName', 'setOptionValue')
	 *		.modalWindow('modalwindowshow', function( event ){}); // bind some event
	 *	</pre>
	 */

	var LJModalWindow = {
		/** @lends $.lj.modalWindow.prototype */
		options: {
			width: 800,
			height: 500,
			selectors: {
				closeBtn: '.i-popup-close',
				contentNode: '.b-popup-content'
			},
			templates: {
				popup: '<div class="b-popup">' +
					'<div class="b-popup-outer">' +
						'<div class="b-popup-inner">' +
							'<div class="popup-inner">' +
								'<div class="b-popup-content"></div>' +
								'<i class="i-popup-close"></i>' +
							'</div>' +
						'</div>' +
					'</div>' +
				'</div>',
				fader: '<div class="b-fader"></div>'
			}

		},

		/**
		 * @private
		 */
		_create: function () {
			this._makeNodes();
		},

		/**
		 * @private
		 */
		_makeNodes: function () {
			var options = this.options;
			var selectors = options.selectors;

			this._popupNode = $(options.templates.popup);
			this._faderNode = $(options.templates.fader);
			this._closeBtn = this._popupNode.find(selectors.closeBtn);
			this._contentNode = this._popupNode.find(selectors.contentNode);
			this._contentNode.append(this.element);

			this._bindEvents();
		},

		/**
		 * @private
		 */
		_bindEvents: (function () {
			function onClose (evt) {
				evt.preventDefault();
				evt.data.hide();
			}

			function onCloseEsc (evt) {
				if (evt.which == 27) { // Escape
					onClose(evt);
				}
			}

			return function () {
				var options = this.options;
				var selectors = options.selectors;

				this._popupNode
					.delegate(selectors.closeBtn, 'click', this, onClose);

				this._faderNode.bind('click', this, onClose);

				$(document).bind('keydown', this, onCloseEsc);
			}
		})(),

		/**
		 * @private
		 */
		_setOption: function (option, value) {
			switch (option) {
				case 'content':
					this.element
						.empty()
						.append(value);
				break;
			}

			this.options[option] = value;
		},

		/**
		 * Update the position of the window.
		 * @function
		 */
		updatePosition: function () {
			var width = isNaN(this.options.width) ? this._popupNode.width() : this.options.width;

			this._popupNode.css({
				left: - width / 2,
				top: $(window).scrollTop() + ($(window).height() * 0.1),
				marginLeft: '50%'
			});
		},

		/**
		 * Show window.
		 * @function
		 */
		show: function () {
			if (!isNaN(this.options.width)) {
				this._contentNode.css('width', this.options.width);
			}

			if (!isNaN(this.options.height)) {
				this._contentNode.css('height', this.options.height);
			}

			this.updatePosition();

			$(document.body)
				.append(this._faderNode)
				.append(this._popupNode);
			
			this._trigger('show');
		},

		/**
		 * Hide window.
		 * @function
		 */
		hide: function () {
			this._faderNode.detach();
			this._popupNode.detach();
			this._trigger('hide');
		}
	};

	$.widget('lj.modalWindow', LJModalWindow);
})(jQuery, this);

/**
 * @name $.lj.modalWindow#modalwindowshow
 * @event
 * @param {Object} evt jQuery event object
 * @description The event window is show {@link $.lj.modalWindow#show}.
 */

/**
 * @name $.lj.modalWindow#modalwindowhide
 * @event
 * @param {Object} evt jQuery event object
 * @description The event window is hide {@link $.lj.modalWindow#hide}.
 */