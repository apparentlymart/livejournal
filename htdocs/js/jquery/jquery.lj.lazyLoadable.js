 /**
 * @author dmitry.petrov@sup.com (Dmitry Petrov)
 * @fileoverview LiveJournal widget representing block that appends itself as user scrolls the page
 */

/**
 * @name $.lj.selfPromoStatsTable
 * @requires $.ui.core, $.ui.widget, $.lj.basicWidget
 * @class Widget represents block that appends itself as user scrolls the page.
 * @extends $.lj.basicWidget
 *
 */
(function($,window) {

	var $window = jQuery(window);

	/** @lends $.lj.lazyLoadable.prototype */
	$.widget('lj.lazyLoadable', jQuery.lj.basicWidget, {
		options: {
			selectors: {
				row: '.b-row',
				container: null, //null means that this.element is the container
				loadMore: 'b-load-more'
			},
			classNames: {
				loading: '',
				noMoreRows: 'b-nomore',
				oddRow: ''
			},

			pageSize: 10,
			treshold: 500, //px
			url: LiveJournal.constructUrl(location.href, {offset: '{offset}'})
		},

		_create: function() {
			var selectors = this.options.selectors;

			$.lj.basicWidget.prototype._create.apply(this);

			this._eventNamespace = '.' + this.widgetName;
			this._container = selectors.container ? this.element.find(selectors.container) : this.element;
			this._loadMore = this.element.find(selectors.loadMore);
			this._count = this.options.pageSize;

			this._firstOdd = true;
			this._lastOdd = this._count % 2 === 1;
			this._containerBottom = this._container.offset().top + this._container.height();
			this._bindControls();
		},

		_bindControls: function() {
			var self = this,
				selectors = this.options.selectors,
				classNames = this.options.classNames;

			this._loading = false;
			$window.bind('scroll' + this._eventNamespace, this._onScroll.bind(this));

			$.lj.basicWidget.prototype._bindControls.apply(this);
		},

		_onScroll: function(ev) {
			if (this._loading) { return; }

			if ((this._containerBottom - this.options.treshold) <= ($window.scrollTop() + $window.height())) {
				this._loadRows();
			}
		},

		_loadRows: function() {
			var self = this;
			this._loading = true;

			var errorHandler = function() {
				setTimeout(function() {
					self._loadRows();
				}, 3000);
			};

			jQuery
				.getJSON(this.options.url.supplant({offset: this._count}))
				.success(this._onHandleLoadRows.bind(this))
				.error(errorHandler);
		},

		_onHandleLoadRows: function(ans) {
			if (!ans.status === 'ok') { return; }

			this._onLoadRows(ans);
			this._setCount(this._count + ans.rows.length);
			this._containerBottom = this._container.offset().top + this._container.height();

			if (ans.rows.length < this.options.pageSize) {
				this._loadMore.addClass(this.options.classNames.noMoreRows);
				$window.unbind('scroll' + this._eventNamespace);
			}
			this._loading = false;
		},

		_onLoadRows: function(ans) {
			var count = this._count,
				lastOdd = this._lastOdd;
				odd = this.options.classNames.oddRow,
				oddClass = function(idx) {
					var num = idx % 2;
					return (num === ( lastOdd ? 1 : 0)) ? odd : '';
				},
				html = ans.rows.reduce(function(html, row, idx) { 
								return html + row.html.supplant({ oddClass: oddClass(idx) }); }, '');
			this._container.append(html);
		},

		_recalcRows: function() {
			this._setCount(this.container.find(this.options.selectors.row).length);
		},

		_setCount: function(count) {
			this._count = count;
			this._lastOdd = this._count % 2 === 1;
		}
	});

})(jQuery, window);

