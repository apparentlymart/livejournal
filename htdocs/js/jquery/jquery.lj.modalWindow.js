(function ($, window) {

	var LJModalWindow = {

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

		_create: function () {
			this._makeNodes();
		},

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

		updatePosition: function () {
			var width = isNaN(this.options.width) ? this._popupNode.width() : this.options.width;

			this._popupNode.css({
				left: - width / 2,
				top: $(window).scrollTop() + ($(window).height() * 0.1),
				marginLeft: '50%'
			});
		},

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

		hide: function () {
			this._faderNode.detach();
			this._popupNode.detach();
			this._trigger('hide');
		}
	};

	$.widget('lj.modalWindow', LJModalWindow);
})(jQuery, this);
