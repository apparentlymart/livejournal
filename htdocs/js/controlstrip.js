jQuery(function($){
	!document.getElementById('lj_controlstrip') &&
	!document.getElementById('lj_controlstrip_new') &&
		$.get(LiveJournal.getAjaxUrl('controlstrip'),
			{ user: Site.currentJournal },
			function(data)
			{
				$(data).appendTo(document.body).ljAddContextualPopup();
			}
		);
});

(function( $, top ) {

var ControlStrip = top.ControlStrip = {};

var CONFIG = {
	rootSelector: ".w-cs",
	overlaysSelectors: [".w-cs-share", ".w-cs-filter", ".i-calendar"],
	showOverlayClass: "w-cs-hover",
	calendarSelector: ".i-calendar"
}

var options, elements;

ControlStrip.init = function( o ) {
	options = $.extend( {}, CONFIG, o );

	elements = {
		root: $( options.rootSelector ),
		calendar: $( options.calendarSelector ),
		overlays: $( options.overlaysSelectors.join(',') )
	}

	elements.root.find('input')
		.filter('[type=\'text\']').labeledPlaceholder().end()
		.filter('[type=\'password\']').labeledPlaceholder().end();

	ControlStrip.initOverlays( elements.overlays );
	if( elements.calendar.size() > 0 ) {
		var d = new Date().setFullYear( 2010, 7, 15 );
		ControlStrip.Calendar.call( elements.calendar );
	}
}

ControlStrip.initOverlays = function( nodes ) {
	nodes.removeClass( options.showOverlayClass );

	nodes.each( function() {
		var $this = $( this ),
			outTimer = null;

		$this.mouseover( function() {
			nodes.removeClass( options.showOverlayClass );
			$this.addClass( options.showOverlayClass );
			clearTimeout( outTimer );
		} )
		.mouseout( function() {
			outTimer = setTimeout( function() {
				$this.removeClass( options.showOverlayClass );
			}, 600 );
		} );
	} );
};

ControlStrip.Calendar = function( o ) {

	var options = {
		monthNames: [ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" ],
		dayRef: "/%Y/%M/%D",
		currentDate: new Date(),
		startAtSunday: true
	},
	$ = jQuery;

	o = $.extend( {}, options, o);

	if( ControlStrip.Calendar.MonthNames ) {
		o.monthNames = ControlStrip.Calendar.MonthNames;
	}

	if( ControlStrip.Calendar.StartAtSunday ) {
		o.startAtSunday = ControlStrip.Calendar.StartAtSunday;
	}

	function getDaysInMonth( date ) {
		var monthArr = [ 31, (isLeapYear(date.getFullYear())?29:28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];
		return monthArr[ date.getMonth() ];
	}

	function isLeapYear(year){
		return ( year % 4 === 0 && (year % 100 != 0 ) ) || ( year % 400 == 0);
	}

	var View = function (nodes, styles, controller)
	{
		this.activeLabelsEvents = {}

		this.initialize = function (monthDate, events, switcherStates)
		{
			this.tbody = this.catchTableStructure();

			//this.fillDates(monthDate, events);
			//this.fillLabels(monthDate, switcherStates)
			this.switcherStates = switcherStates;
			this.bindEvents();
		}

		this.modelChanged = function (monthDate, events, switcherStates)
		{
			//we have a 30% speedup when we temporary remove tbody from dom
			this.tbody.remove();
			this.fillDates(monthDate, events)
			this.fillLabels(monthDate, switcherStates)
			this.tbody.appendTo( nodes.table );
		}

		this.catchTableStructure = function() {
			var tbody = nodes.table[0].tBodies[0];
			nodes.lastRow = $( tbody.rows[ tbody.rows.length - 1 ] );
			nodes.daysCells = [];

			for( row = 0, rowsCount = tbody.rows.length; row < rowsCount; ++row ) {
				for( cell = 0, cellsCount = tbody.rows[ row ].cells.length; cell < cellsCount; ++cell ) {
					nodes.daysCells.push( $( tbody.rows[ row ].cells[ cell ] ) );
				}
			}

			return $( tbody );
		}

		this.fillDates = function (monthDate, events)
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

				this.formDayString( iDate, nodes.daysCells[ h ]);
			}

			for (var i = 1; i <= length; i++)
			{	// body
				var iDate = new Date(monthDate);
				iDate.setDate(i);

				this.formDayString( iDate, nodes.daysCells[ i + offset ], true, events );
			}

			for (var j = i + offset, k = 1; j < nodes.daysCells.length; j++)
			{	// tail
				var iDate = new Date(nextMonth);
				iDate.setDate(k);

				this.formDayString( iDate, nodes.daysCells[j] );
				++k;
			}

			this.toggleExtraWeek(monthDate.getDay() > 5);
		}

		this.toggleExtraWeek  = function (show)
		{
			nodes.lastRow[show ? 'show' : 'hide']();
		}

		this.formDayString = function( d, label, isActive, events )
		{
			events = events || [];
			isActive = isActive || false;

			function getDateNumber( d ) {
				var day = d.getDate().toString();
				if( day.length == 1 ) { day = "0" + day; }

				var month = d.getMonth().toString();
				if( month.length == 1 ) { month = "0" + month; }

				return parseInt( d.getFullYear().toString() + month + day, 10)
			}

			var today = new Date(),
				isInFuture = ( getDateNumber( d ) > getDateNumber( today ) ),
				isCurrentDay = ( getDateNumber( d ) == getDateNumber( o.currentDate ) ),
				hasEvents = ( $.inArray( d.getDate(), events ) > -1 );

			label[isCurrentDay ? 'addClass' : 'removeClass']( styles.current );

			if( !isActive || isInFuture ) {
				label.addClass( styles.inactive ).html(d.getDate());
			} else if( hasEvents ) {

				var ref = o.dayRef,
					subs = [ [ '%Y', d.getFullYear()], [ '%M', d.getMonth() + 1], [ '%D', d.getDate()] ];
				for( var i = 0; i < subs.length; ++i ) {
					ref = ref.replace( subs[i][0], subs[i][1] );
				}

				label.removeClass( styles.inactive ).html( $("<a>")
						.html( d.getDate() )
						.attr( 'href', ref ) );
			} else {
				label.removeClass( styles.inactive ).html(d.getDate());
			}
		}

		this.bindEvents = function ()
		{
			var that = this;
			for (var sws in this.switcherStates) {
				nodes[sws].mousedown( function (item) { return function ( ev ) {
					if(that.switcherStates[item]) {
						that.controller[item]();
					}

					ev.preventDefault();
				} }(sws));
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

	var Controller = function (view, model)
	{
		this.prevMonth = function () { model.switchMonth(-1); };
		this.nextMonth = function () { model.switchMonth( 1); };

		this.prevYear  = function () { model.switchYear(-1); };
		this.nextYear  = function () { model.switchYear( 1); };

		view.controller = this;
		model.initialize();
	}

	var Model = function ( selectedDay, view)
	{
		this.enabledMonthsRange = [];
		this.datesCache = {};
		//if ajax request is already sent, we do not change the model before the answer
		this.ajaxPending = false;

		this.initialize = function ()
		{
			var startDate = new Date();
			startDate.setFullYear( 1999, 3, 15 );
			this.enabledMonthsRange = [ startDate, new Date()];
			this.monthDate = new Date( selectedDay );
			view.initialize(this.monthDate, null, this.getSwitcherStates(this.monthDate));
			this.switchMonth( 0 );
		}

		this.switchMonth = function (go)
		{
			this.monthDate.setMonth(this.monthDate.getMonth() + go);
			var self = this;
			this.fetchMonthEvents( this.monthDate, function( events ) {
				view.modelChanged(self.monthDate, events, self.getSwitcherStates( self.monthDate ) );
			} )
		}

		this.switchYear = function (go)
		{
			this.monthDate.setFullYear(this.monthDate.getFullYear() + go, this.monthDate.getMonth(), this.monthDate.getDate());
			while( !this.insideRange( this.enabledMonthsRange, this.monthDate ) ) {
				this.monthDate.setMonth( this.monthDate.getMonth() - 1 );
			}
			var self = this;
			this.fetchMonthEvents( this.monthDate, function( events ) {
				view.modelChanged(self.monthDate, events, self.getSwitcherStates( self.monthDate ) );
			} )
		}

		//now we generate random data, because endpoint does not exist. FIXIT
		this.fetchMonthEvents = function( date, onFetch ) {
			if( this.ajaxPending ) {
				return;
			}
			this.ajaxPending = true;
			var hash = date.getFullYear() + "-",
				month = (date.getMonth() + 1).toString();

			hash += ( (month.length == 1) ? "0" : "" ) + month;

			if( hash in this.datesCache ) {
				this.ajaxPending = false;
				onFetch( this.datesCache[ hash ].slice( 0 ) );
			} else {
				var self = this;
				//here we emulate ajax request
				setTimeout( function() {
					var daysNum = date.getMonth(),
						result = [];

					for( var i = 1; i <= daysNum; ++i ) {
						if( Math.random() > 0.5 ) {
							(function( day ) {
								result.push( day );
							}(i));
						}
					}

					self.datesCache[ hash ] = result.slice( 0 );
					self.ajaxPending = false;
					onFetch( result.slice( 0 ) );
				}, 0 );
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
			prevYear.setFullYear(monthDate.getFullYear() - 1, monthDate.getMonth(), monthDate.getDate());
			var py = this.insideRange(this.enabledMonthsRange, prevYear);

			var nextYear = new Date(monthDate);
			nextYear.setFullYear(monthDate.getFullYear() + 1, 0, 1 );
			var ny = this.insideRange(this.enabledMonthsRange, nextYear);

			return { prevMonth: pm, nextMonth: nm, prevYear: py, nextYear: ny };
		}

		this.insideRange = function (range, iDate) { return iDate >= range[0] && iDate <= range[1] };
	}

	var nodes =
	{
		container: this,
		table: this.find('table'),

		prevMonth: this.find('.cal-nav-month .cal-nav-prev'),
		nextMonth: this.find('.cal-nav-month .cal-nav-next'),
		prevYear:  this.find('.cal-nav-year .cal-nav-prev'),
		nextYear:  this.find('.cal-nav-year .cal-nav-next'),

		monthLabel: this.find('.cal-nav-month .cal-month'),
		yearLabel: this.find('.cal-nav-year .cal-year')
	}

	var styles =
	{
		inactive : 'other',
		hasEvents: '',
		current  : 'current',
		future: 'other',

		nextDisabled : 'cal-nav-next-dis',
		prevDisabled : 'cal-nav-prev-dis'
	}

	var view = new View(nodes, styles);
	var model = new Model( o.currentDate, view);
	var controller = new Controller(view, model);
};

}( jQuery, window ));
