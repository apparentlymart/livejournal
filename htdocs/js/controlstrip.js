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
	o = o || {};

	if( ControlStrip.Calendar.MonthNames ) {
		o.monthNames = ControlStrip.Calendar.MonthNames;
	}

	if( ControlStrip.Calendar.StartAtSunday ) {
		o.startAtSunday = ControlStrip.Calendar.StartAtSunday;
	}

	var onFetch = function( onload ) {
		jQuery.getJSON( LiveJournal.getAjaxUrl('get_posting_days'),
			{ journal: Site.currentJournal }, onload );
	}

	this.calendar( {
		onFetch: onFetch,
		activeUntil: new Date(),
		startMonth: new Date( 1999, 3, 1 ),
		endMonth: new Date()
	} );
};

}( jQuery, window ));
