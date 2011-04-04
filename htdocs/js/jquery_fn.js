jQuery.noConflict();

jQuery.ajaxSetup({
	cache: false
});

jQuery.fn.ljAddContextualPopup = function()
{
	if (!window.ContextualPopup) return this;
	
	return this.each(function()
	{
		ContextualPopup.searchAndAdd(this);
	});
}

jQuery.fn.hourglass = function(xhr)
{
	var hourglasses = [];
	this.each(function()
	{
		// is complete or was aborted
		if (xhr && (xhr.readyState == 0 || xhr.readyState == 4)) return;
		
		if (this.nodeType) { // node
			
		} else { // position from event
			var e = jQuery.event.fix(this),
				hourglass = new Hourglass(),
				offset = {};
			
			// from keyboard
			if (!e.clientX || !e.clientY) {
				offset = jQuery(e.target).offset();
			}
			
			hourglass.init();
			hourglass.hourglass_at(offset.left || e.pageX, offset.top || e.pageY);
		}
		
		hourglasses.push(hourglass)
		
		if (xhr)
		{
			jQuery(hourglass.ele).bind('ajaxComplete', function(event, request)
			{
				if (request == xhr) {
					hourglass.hide();
					jQuery(hourglass.ele).unbind('ajaxComplete', arguments.callee);
				}
			});
		}
	});
	
	return hourglasses;
}

// not work for password
jQuery.fn.placeholder = (function()
{
	var check_focus = function() {
			if (this.value === this.getAttribute("placeholder")) {
				jQuery(this)
					.val("")
					.removeClass("placeholder");
			}
		},
		check_blur = function() {
			if (!this.value) {
				jQuery(this)
					.val(this.getAttribute("placeholder"))
					.addClass("placeholder");
			}
		},
		support;

	return function() {
		if (support === undefined) {
			support = "placeholder" in document.createElement("input");
		}
		if (support === true) {
			return this;
		} else {
			return this.each(function() {
				if (this.getAttribute("placeholder")) {
					var $this = jQuery(this);
					
					if (!$this.data('jQuery-has-placeholder')) {
						$this.focus(check_focus).blur(check_blur);

						jQuery(this.form)
							.submit(function() {
								$this.hasClass("placeholder") && $this.removeClass("placeholder").val("");
							});
					}

					this.value === this.getAttribute("placeholder") || !this.value
						? $this.val(this.getAttribute("placeholder")).addClass("placeholder")
						: $this.removeClass("placeholder");

					$this.data('jQuery-has-placeholder', true)
				}
			});
		}
	}
})();

//this one is fields type agnostic but creates additional label elements, which need to be styled
jQuery.fn.labeledPlaceholder = function() {
	function focus_action( input, label ) {
		label.hide();
	}

	function blur_action( input, label ) {
		if( input.val().length === 0 ) {
			label.show();
		}
	}

	return this.each( function() {

		if ('placeholder' in document.createElement('input') && this.tagName.toLowerCase() === "input" ) {
			return;
		}
		if ('placeholder' in document.createElement('textarea') && this.tagName.toLowerCase() === "textarea" ) {
			return;
		}

		var $this = jQuery( this ),
			placeholder = $this.attr( 'placeholder' );

		if( !placeholder || placeholder.length === 0 ) { return; }

		var label = jQuery( "<label></label>")
				.css({
					position: "absolute",
					cursor: "text",
					display: "none"
					})
				.addClass('placeholder-label')
				.mousedown(function( ev ) {
					setTimeout( function() {
						focus_action( $this, label )
						$this.focus();
					}, 0);
				} )
				.html( placeholder )
				.insertBefore( $this );
		$this.focus( function() { focus_action( $this, label ) } )
			.blur( function() { blur_action( $this, label ) } );

		blur_action( $this, label );
	} );
}

jQuery.fn.input = function(fn) {
	return fn
		? this.each(function() {
			var last_value = this.value;
			jQuery(this).bind("input keyup paste", function(e) {
				// e.originalEvent use from trigger
				if (!e.originalEvent || this.value !== last_value) {
					last_value = this.value;
					fn.apply(this, arguments);
				}
			})
		})
		: this.trigger("input");
}

// ctrl+enter send form
jQuery.fn.disableEnterSubmit = function() {
	this.bind("keypress", function(e) {
		// keyCode == 10 in IE with ctrlKey
		if ((e.which === 13 || e.which === 10) && e.target && e.target.form) {
			if (e.target.tagName === "TEXTAREA" && e.ctrlKey && !jQuery(":submit", e.target.form).attr("disabled")) {
				e.target.form.submit();
			} else if (e.target.type === "text" && !e.ctrlKey) { // for input:text
				e.preventDefault();
			}
		}
	});
	return this;
};

/* function based on markup:
	tab links: ul>li>a
	current tab: ul>li.current
	tab container: ul>li
	tab container current: ul>li.current
*/
jQuery.fn.tabsChanger = function(container)
{
	var links = this.children("li").children("a");
	
	if (container) {
		container = jQuery(container);
	} else {
		// next sibling of links
		container = links.parent().parent().next();
	}
	
	links.click(function(e)
	{
		var item = jQuery(this).parent(),
			index = item.index(),
			containers = container.children("li");

		if (containers[index]) {
			links.parent().removeClass("current");
			item.addClass("current");

			containers.removeClass("current")
				.eq(index)
				.addClass("current");

			e.preventDefault();
		}
	});

	return this;
}

/** jQuery overlay plugin
 * After creation overlay visibility can be toggled with
 * $( '#selector' ).overlay( 'show' ) and $( '#selector' ).overlay( 'hide' )
*/
jQuery.fn.overlay = function( opts ) {
	var options = {
			hideOnInit: true,
			hideOnClick: true
		};

	function Overlay( layer, options) {
		this.layer = jQuery( layer );
		this.options = options;
		this.updateState( this.options.hideOnInit );
		this.bindEvents();
	}

	Overlay.prototype.bindEvents = function() {
		var overlay = this;

		if( this.options.hideOnClick ) {
			overlay.layer.mousedown( function( ev ) {
				ev.stopPropagation();
			} );

			jQuery( document ).mousedown(function( ev ) {
				overlay.updateState( true );
				ev.stopPropagation();
			} );
		}
	};

	Overlay.prototype.updateState = function( hide ) {
		this.layerVisible = !hide;
		if( this.layerVisible ) {
			this.layer.show();
		} else {
			this.layer.hide();
		}
	}

	Overlay.prototype.proccessCommand = function ( cmd ) {
		switch( cmd ) {
			case 'show' :
				this.updateState( false );
				break;
			case 'hide' :
				this.updateState( true );
				break;
		}
	}

	var cmd;
	if( typeof opts === "string" ) {
		cmd = opts;
	}

	return this.each( function() {
		if( !this.overlay ) {
			var o = jQuery.extend( {}, options, opts || {} );
			this.overlay = new Overlay( this, o );
		}

		if( cmd.length > 0 ) {
			this.overlay.proccessCommand( opts )
		}
	});
}
jQuery.fn.calendar = function( o ) {
	//global variables for all instances
	var defaultOptions = {
		monthNames: [ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" ],
		dayRef: "/%Y/%M/%D",
		onFetchMonth: null,
		currentDate: new Date(),
		//allow user to select dates in this range
		activeUntil: null,
		activeFrom: null,
		//allow user to switch months between these dates
		startMonth: null,
		endMonth: null,
		startAtSunday: true
	};

	var nodeSelectors =
	{
		table: 'table',

		prevMonth: '.cal-nav-month .cal-nav-prev',
		nextMonth: '.cal-nav-month .cal-nav-next',
		prevYear:  '.cal-nav-year .cal-nav-prev',
		nextYear:  '.cal-nav-year .cal-nav-next',

		monthLabel: '.cal-nav-month .cal-month',
		yearLabel: '.cal-nav-year .cal-year'
	}

	var styles =
	{
		inactive : 'other',
		future : 'other',
		current  : 'current',
		nextDisabled : 'cal-nav-next-dis',
		prevDisabled : 'cal-nav-prev-dis',
		cellHover : 'hover'
	}

	function initCalendar( node, options ) {
		var nodes = { container: node };
		for( var i in nodeSelectors ) {
			nodes[ i ] = nodes.container.find( nodeSelectors[ i ] );
		}

		var view = new View(nodes, styles, options);
		var model = new Model( options.currentDate, view, options);
		var controller = new Controller(view, model, options);
	}

	function getDateNumber( d, dropDays ) {
		dropDays = dropDays || false;
		var day = d.getDate().toString();
		if( day.length == 1 ) { day = "0" + day; }
		if( dropDays ) {
			day = "";
		}

		var month = d.getMonth().toString();
		if( month.length == 1 ) { month = "0" + month; }

		return parseInt( d.getFullYear().toString() + month + day, 10)
	}

	function getDaysInMonth( date ) {
		var monthArr = [ 31, (isLeapYear(date.getFullYear())?29:28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];
		return monthArr[ date.getMonth() ];
	}

	function isLeapYear(year){
		return ( year % 4 === 0 && (year % 100 != 0 ) ) || ( year % 400 == 0);
	}

	function addPadding( str, length, chr ) {
		str = str.toString(); //cast any type to string
		while( str.length < length ) {
			str = chr + str;
		}

		return str;
	}

	var View = function (nodes, styles, o)
	{
		this.initialize = function (monthDate, events, switcherStates)
		{
			this.tbody = this.catchTableStructure();

			this.switcherStates = switcherStates;
			this.bindEvents();
		}

		this.modelChanged = function (monthDate, selectedDay, events, switcherStates)
		{
			//we have a 30% speedup when we temporary remove tbody from dom
			this.tbody.detach();
			this.fillDates(monthDate, selectedDay, events)
			this.fillLabels(monthDate, switcherStates)
			this.tbody.appendTo( nodes.table );
		}

		this.dateSelected = function( date )
		{
			for( var i = 0; i < nodes.daysCells.length; ++i ) {
				if( getDateNumber( date ) == getDateNumber( nodes.daysCells[ i ].data( 'day' ) ) ) {
					nodes.daysCells[ i ].addClass( styles.current );
				} else {
					nodes.daysCells[ i ].removeClass( styles.current );
				}
			}
		}

		this.catchTableStructure = function() {
			var tbody = nodes.table[0].tBodies[0];
			nodes.lastRow = jQuery( tbody.rows[ tbody.rows.length - 1 ] );
			nodes.daysCells = [];

			for( row = 0, rowsCount = tbody.rows.length; row < rowsCount; ++row ) {
				for( cell = 0, cellsCount = tbody.rows[ row ].cells.length; cell < cellsCount; ++cell ) {
					var node = jQuery( tbody.rows[ row ].cells[ cell ] );
					nodes.daysCells.push( node );
				}
			}

			return jQuery( tbody );
		}

		this.fillDates = function (monthDate, selectedDay, events)
		{
			var firstDay = new Date(monthDate);
			firstDay.setDate(1);

			var offset;
			if( o.startAtSunday ) {
				offset = firstDay.getDay() - 1;
			} else {
				offset = (firstDay.getDay() == 0 ? 5: firstDay.getDay() - 2);
			}

			var length = getDaysInMonth( monthDate );

			var prevMonth = new Date(monthDate);
			prevMonth.setMonth(monthDate.getMonth() - 1);
			var prLength = getDaysInMonth( prevMonth );

			var nextMonth = new Date(monthDate)
			nextMonth.setMonth(monthDate.getMonth() + 1)

			for (var h = offset, l = prLength; h >= 0; h--)
			{	// head
				var iDate = new Date(prevMonth);
				iDate.setDate(l--);

				this.formDayString( iDate, nodes.daysCells[ h ], null, this.isActiveDate(iDate, monthDate ), selectedDay );
			}

			for (var i = 1; i <= length; i++)
			{	// body
				var iDate = new Date(monthDate);
				iDate.setDate(i);

				this.formDayString( iDate, nodes.daysCells[ i + offset ], events, this.isActiveDate(iDate, monthDate ), selectedDay );
			}

			for (var j = i + offset, k = 1; j < nodes.daysCells.length; j++)
			{	// tail
				var iDate = new Date(nextMonth);
				iDate.setDate(k);

				this.formDayString( iDate, nodes.daysCells[j], null, this.isActiveDate(iDate, monthDate ), selectedDay );
				++k;
			}

			this.toggleExtraWeek(monthDate.getDay() > 5);
		}

		this.toggleExtraWeek  = function (show)
		{
			nodes.lastRow[show ? 'show' : 'hide']();
		}

		this.isActiveDate = function( date, currentMonth ) {
			var isActive = true;

			isActive = ( currentMonth.getFullYear() === date.getFullYear() && currentMonth.getMonth() === date.getMonth() );

			if( isActive && ( o.activeFrom || o.activeUntil ) ) {
				isActive = ( o.activeFrom && getDateNumber( o.activeFrom ) <= getDateNumber( date ) )
				|| ( o.activeUntil && getDateNumber( o.activeUntil ) >= getDateNumber( date ) );
			}

			return isActive;
		}

		this.formDayString = function( d, label, events, isActive, selectedDay )
		{
			events = events || [];
			label.data( 'day', d );
			label.data( 'isActive', isActive );

			var today = new Date(),
				isCurrentDay = ( getDateNumber( d ) == getDateNumber( selectedDay ) ),
				hasEvents = ( jQuery.inArray( d.getDate(), events ) > -1 );

			label[isCurrentDay ? 'addClass' : 'removeClass']( styles.current );

			if( !isActive ) {
				label.addClass( styles.inactive ).html(d.getDate());
			} else if( hasEvents ) {

				var ref = o.dayRef,
					subs = [ [ '%Y', d.getFullYear()], [ '%M', addPadding( d.getMonth() + 1, 2, "0" ) ], [ '%D', addPadding( d.getDate(), 2, "0" ) ] ];
				for( var i = 0; i < subs.length; ++i ) {
					ref = ref.replace( subs[i][0], subs[i][1] );
				}

				label.removeClass( styles.inactive ).html( jQuery("<a>")
						.html( d.getDate() )
						.attr( 'href', ref ) );
			} else {
				label.removeClass( styles.inactive ).html(d.getDate());
			}
		}

		this.bindEvents = function ()
		{
			var self = this;
			for (var sws in this.switcherStates) {
				nodes[sws].mousedown( function (item) { return function ( ev ) {
					if(self.switcherStates[item]) {
						self.controller[item]();
					}

					ev.preventDefault();
				} }(sws));
			}

			var cells = nodes.daysCells;
			for( var i = 0, l = cells.length; i < l; ++i ) {
				cells[i].mouseover( function() {
						var cell = jQuery( this );
						cell.data( 'isActive' ) && cell.addClass( styles.cellHover );
					} )
					.mouseout( function() {
						var cell = jQuery( this );
						cell.removeClass( styles.cellHover );
					} )
					.click( function() {
						var cell = jQuery( this );
						if( cell.data( 'isActive' ) ) {
							self.controller.cellSeleted( cell.data( 'day' ) );
						}
					} );
			}
		}

		this.fillLabels = function (monthDate, switcherStates)
		{
			this.switcherStates = switcherStates
			for (var sws in switcherStates)
			{
				if(!switcherStates[sws]) {
					nodes[sws].addClass(this.disabledStyle(sws));
				}
				else {
					nodes[sws].removeClass(this.disabledStyle(sws));
				}
			}
			nodes.monthLabel.html( o.monthNames[ monthDate.getMonth() ] );
			nodes.yearLabel.html ( monthDate.getFullYear() );
		}

		this.disabledStyle = function (sws)
		{
			if(sws == 'prevMonth' || sws == 'prevYear') return styles.prevDisabled;
			else return styles.nextDisabled;
		}
	}

	var Controller = function (view, model, o )
	{
		this.prevMonth = function () { model.switchMonth(-1); };
		this.nextMonth = function () { model.switchMonth( 1); };

		this.prevYear  = function () { model.switchYear(-1); };
		this.nextYear  = function () { model.switchYear( 1); };

		this.cellSeleted = function( date ){
			if( o.onDaySelected && view.isActiveDate( date, model.monthDate ) ) {
				o.onDaySelected( date );
				model.selectDate( date );
			}
		};

		view.controller = this;
		model.initialize();
	}

	var Model = function( selectedDay, view, options )
	{
		this.events = null;

		this.initialize = function ()
		{
			var self = this;
			var startMonth = options.startMonth || new Date( 1900, 0, 1 ),
				endMonth = options.endMonth || new Date( 2050, 0, 1 );
			startMonth.setDate( 1 );
			this.enabledMonthsRange = [ startMonth, endMonth ];
			this.monthDate = new Date( selectedDay );
			this.selectedDay = new Date( selectedDay );

			function bootstrapView() {
				view.initialize( self.monthDate, null, self.getSwitcherStates( self.monthDate ) );
				self.switchMonth( 0 );
			}

			if( !options.onFetch ) {
				bootstrapView();
			} else {
				options.onFetch( function( events ) {
					self.events = self.initEvents( events );
					bootstrapView();
				} );
			}
		}

		this.switchMonth = function (go)
		{
			var dir = go || -1;
			var date = new Date( this.monthDate );
			date.setMonth(date.getMonth() + go);
			this.switchDate( date, dir );
		}

		this.switchYear = function (go)
		{
			var sgn = ( go > 0 ) ? 1 : ( go < 0 ) ? - 1 : 0,
				count = sgn * ( ( Math.abs( go )  ) * 12 );
			this.switchMonth( count );
		}

		this.initEvents = function( data ) {
			return function() {
				var datesArr = [];
				var datesCache = [];

				if( typeof data === "object" ) {
					var id = "";
					for( var year in data ) {
						for( var month in data[ year ] ) {
							id = makeHash( year, month );
							datesCache[ id ] = jQuery.map( data[ year ][ month ], function( item ) { return parseInt( item, 10 ); } );
							datesArr.push( id );
						}
					}
				}
				datesArr.sort();

				function outOfBounds( date ) {
					return ( datesArr.length === 0 || date < datesArr[ 0 ] || date > datesArr[ datesArr.length - 1 ] );
				}

				function makeHash( year, month ) {
					year = year.toString(); month = month.toString();
					return parseInt( year + ( (month.length == 1) ? "0" : "" ) + month, 10 );
				}

				return {
					getPrev: function( date ) {
						if( outOfBounds( date ) ) { return false; }
						for( var i = datesArr.length - 1; i >= 0 ; --i ) {
							if( datesArr[ i ] < date ) {
								return datesCache[ i ];
							}
						}
						return false;
					},

					getNext: function( date ) {
						if( outOfBounds( date ) ) { return false; }
						for( var i = 0; i < datesArr.length; ++i ) {
							if( datesArr[ i ] > date ) {
								return datesCache[ i ];
							}
						}
						return false;
					},

					hasEventsAfter: function( date, dir ) {
						var hash = makeHash( date.getFullYear(), date.getMonth() + 1 );
						var arr = jQuery.grep( datesArr, function( n, i ) {
							return ( dir > 0 ) ? n > hash : n < hash;
						} );

						return arr.length > 0;
					},

					getEvents: function( date ) {
						var hash = makeHash( date.getFullYear(), date.getMonth() + 1 );
						return ( hash in datesCache ) ? datesCache[ hash ] : false;
					}
				}
			}();
		}

		this.switchDate = function( date, dir ) {
			dir = dir || -1;
			date = this.fitDate( date, this.monthDate, dir );

			if( date !== false ) {
				this.monthDate = date;

				var events = ( this.events ) ? this.events.getEvents( date ) : null;
				view.modelChanged( date, this.selectedDay, events, this.getSwitcherStates( date ) );
			}
		}

		this.selectDate = function( date ) {
			this.selectedDay = new Date( date );
			view.dateSelected( this.selectedDay );
		}

		this.getSwitcherStates = function (monthDate)
		{
			var yearStart = new Date( monthDate.getFullYear(), 0, 1 ),
				yearEnd = new Date( monthDate.getFullYear(), 11, 1 );

			return {
				prevMonth: this.isActivePrev( monthDate ) !== false,
				prevYear: this.isActivePrev( yearStart ) !== false,
				nextMonth: this.isActiveNext( monthDate ) !== false,
				nextYear: this.isActiveNext( yearEnd ) !== false
			};
		}

		this.isActiveNext = function( date ) { return this.isActiveDate( date, 1 ); };
		this.isActivePrev = function( date ) { return this.isActiveDate( date, -1 ); };
		this.isActiveDate = function( date, dir ) {
			var checkEvents = !!( this.events !== null );
			var d = new Date( date );
			d.setMonth( d.getMonth() + dir );

			return this.insideRange( this.enabledMonthsRange, d ) && ( !checkEvents || this.events.hasEventsAfter( d, dir ) );
		}

		this.fitDate = function( date, currentDate,  dir ) {
			date = new Date( date );
			var checkEvents = !!( this.events !== null );
			if( !this.insideRange( this.enabledMonthsRange, date ) ) {
				if( getDateNumber( date, true ) < getDateNumber( this.enabledMonthsRange[ 0 ], true ) ) {
					date = new Date( this.enabledMonthsRange[ 0 ] );
				} else {
					date = new Date( this.enabledMonthsRange[ 1 ] );
				}
			}

			if( !checkEvents || this.events.getEvents( date ) ) {
				return date;
			}

			saveDate = new Date( date );

			var sgn = ( dir > 0 ) ? 1 : -1;
			while( this.insideRange( this.enabledMonthsRange, date ) && !this.events.getEvents( date ) ) {
				date.setMonth( date.getMonth() + sgn );
				if( this.events.getEvents( date ) ) {
					return date;
				}
			}

			date = saveDate;
			while( ( getDateNumber( date, true ) !== getDateNumber( currentDate, true ) ) ) {
				if( this.events.getEvents( date ) ) {
					return date;
				}
				date.setMonth( date.getMonth() - sgn );
			}

			return false;
		}

		this.insideRange = function (range, iDate) {
			return getDateNumber( iDate, true ) >= getDateNumber( range[0], true )
					&& getDateNumber( iDate, true ) <= getDateNumber( range[1], true );
		};
	}

	return this.each( function() {
		if( "monthNames" in o && o.monthNames == null ) {
			delete o.monthNames;
		}
		var options = jQuery.extend( {}, defaultOptions, o);
		initCalendar( jQuery(this), options );
	} );
}
