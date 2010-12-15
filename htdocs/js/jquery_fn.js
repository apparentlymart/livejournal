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
				var $this = jQuery(this);

				$this.focus(check_focus).blur(check_blur);

				jQuery(this.form)
					.submit(function() {
						$this.hasClass("placeholder") && $this.removeClass("placeholder").val("");
					});

				this.value === this.getAttribute("placeholder") || !this.value
					? $this.val(this.getAttribute("placeholder")).addClass("placeholder")
					: $this.removeClass("placeholder");
			});
		}
	}
})();

//this one is fields type agnostic but creates additional label elements, which need to be styled
jQuery.fn.labeledPlaceholder = function() {
	if ('placeholder' in document.createElement('input')) {
		return this;
	}

	function focus_action( input, label ) {
		label.hide();
	}

	function blur_action( input, label ) {
		if( input.val().length === 0 ) {
			label.show();
		}
	}

	return this.each( function() {
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

	function getDateNumber( d ) {
		var day = d.getDate().toString();
		if( day.length == 1 ) { day = "0" + day; }

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

	var Model = function ( selectedDay, view, options )
	{
		this.enabledMonthsRange = [];
		this.datesCache = null;
		//if ajax request is already sent, we do not change the model before the answer
		this.ajaxPending = false;

		this.initialize = function ()
		{
			var startMonth = options.startMonth || new Date( 1900, 0, 1 ),
				endMonth = options.endMonth || new Date( 2050, 0, 1 );
			this.enabledMonthsRange = [ startMonth, endMonth ];
			this.monthDate = new Date( selectedDay );
			this.selectedDay = new Date( selectedDay );
			view.initialize(this.monthDate, null, this.getSwitcherStates(this.monthDate));
			this.switchMonth( 0 );

			/*
			if( !options.onFetch ) {
				view.initialize(this.monthDate, null, this.getSwitcherStates(this.monthDate));
				this.switchMonth( 0 );
			} else {
				var self = this;
				this.fetchEvents( function( events ) {
					self.initEvents( events );
					view.initialize(this.monthDate, null, this.getSwitcherStates(this.monthDate));
					self.switchMonth( 0 );
				} );
			}
			*/
		}

		this.switchMonth = function (go)
		{
			var date = new Date( this.monthDate );
			date.setMonth(date.getMonth() + go);
			this.switchDate( date, go );
		}

		this.switchYear = function (go)
		{
			var date = new Date( this.monthDate );
			date.setFullYear(date.getFullYear() + go, date.getMonth(), date.getDate());
			if( !this.insideRange( this.enabledMonthsRange, date ) ) {
				var add = getDateNumber( date ) < getDateNumber( this.enabledMonthsRange[ 0 ] ) ? 1 : -1;
				while( !this.insideRange( this.enabledMonthsRange, date ) ) {
					date.setMonth( date.getMonth() + add );
				}
			}
			this.switchDate( date, go );
		}

		this.switchDate = function( date, dir ) {
			dir = dir || -1;
			if( this.ajaxPending ) {
				return;
			}
			this.monthDate = date;

			var self = this;
			this.fetchMonthEvents( this.monthDate, function( events, date ) {
				if( typeof events === "boolean" && events === false ) {
				} else {
					view.modelChanged(self.monthDate, self.selectedDay, events, self.getSwitcherStates( self.monthDate ) );
				}
			}, dir );
		}

		this.selectDate = function( date ) {
			this.selectedDay = new Date( date );
			view.dateSelected( this.selectedDay );
		}

		this.fetchMonthEvents = function( date, onFetch ) {
			this.ajaxPending = true;

			//if there is no resource to fetch data, we think, that every month has events
			if( !options.onFetchMonth ) {
				onFetch( [] );
				this.ajaxPending = false;
			} else {
				var self = this;
				options.onFetchMonth( date, function( data ) {
					self.ajaxPending = false;
					onFetch( data );
				} );
			}
		}

		this.getSwitcherStates = function (monthDate)
		{
			var prevMonth = new Date(monthDate);
			prevMonth.setMonth(prevMonth.getMonth() - 1);
			var pm = this.insideRange(this.enabledMonthsRange, prevMonth);

			var nextMonth = new Date(monthDate)
			nextMonth.setMonth(nextMonth.getMonth() + 1);
			var nm = this.insideRange(this.enabledMonthsRange, nextMonth);

			var prevYear = new Date(monthDate);
			prevYear.setFullYear(monthDate.getFullYear() - 1, 11, 31 );
			var py = this.insideRange(this.enabledMonthsRange, prevYear);

			var nextYear = new Date(monthDate);
			nextYear.setFullYear(monthDate.getFullYear() + 1, 0, 1 );
			var ny = this.insideRange(this.enabledMonthsRange, nextYear);

			return { prevMonth: pm, nextMonth: nm, prevYear: py, nextYear: ny };
		}

		this.insideRange = function (range, iDate) {
			return getDateNumber( iDate ) >= getDateNumber( range[0] )
					&& getDateNumber( iDate ) <= getDateNumber( range[1] )
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
