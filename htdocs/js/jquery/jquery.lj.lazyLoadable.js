 /**
 * @author dmitry.petrov@sup.com (Dmitry Petrov)
 * @fileoverview LiveJournal widget representing block that appends itself as user scrolls the page
 */

/**
 * @name $.lj.lazyLoadable
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
				container: null, //null means that this.element is the container
				loadMore: 'b-load-more' //load more spinner
			},
			classNames: {
				//this class is added if ajax endpoint returned less rows than expected
				noMoreRows: 'b-nomore',
				//pagination button should appear if widget fetches max number of rows per page
				showPageControls: '',
				//class is added to all odd rows
				oddRow: ''
			},

			//this value should be filled if we are viewing non-first page
			startOffset: parseInt(LiveJournal.parseGetArgs().offset, 10) || 0,
			//initial number of rows on the page
			pageSize: 10,
			//max number of rows on the page
			rowsLimit: 100,
			//widget will fetch data if bottom of the screen is closer than
			//this to the end of the widget
			treshold: 500, //px
			//an url to fetch more rows
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
				.getJSON(this.options.url.supplant({offset: this._count + this.options.startOffset}))
				.success(this._onHandleLoadRows.bind(this))
				.error(errorHandler);
		},

		/**
		 * Handle ajax output.
		 *
		 * @param {status: 'ok'|'error', rows: Array.{ id: number, html: string}} ajax response.
		 *    The answer structure expected is encoded in type.
		 */
		_onHandleLoadRows: function(ans) {
			if (!ans.status === 'ok') { return; }

			this._onLoadRows(ans);
			this._setCount(this._count + ans.rows.length);
			this._containerBottom = this._container.offset().top + this._container.height();

			if (ans.rows.length < this.options.pageSize) {
				this._loadMore.addClass(this.options.classNames.noMoreRows);
				$window.unbind('scroll' + this._eventNamespace);
			} else if (this._count >= this.options.rowsLimit) {
				this.element.addClass(this.options.classNames.showPageControls);
				this._updatePagination();
				$window.unbind('scroll' + this._eventNamespace);
			}

			this._loading = false;
		},

		/**
		 * Append new rows at the end of the table. This method should be redefined to add
		 *     any custom logic.
		 *
		 * @param {status: 'ok'|'error', rows: Array.{ id: number, html: string}} ajax response.
		 */
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

		/**
		 * Method is called when pagination buttons are shown, so developer can update
		 *     button links.
		 */
		_updatePagination: function() {
		},

		_setCount: function(count) {
			this._count = count;
			this._lastOdd = this._count % 2 === 1;
		}
	});

})(jQuery, window);

