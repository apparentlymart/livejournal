gadgets.util = gadgets.util || {};

(function() {

	var domLoaded = false,
		domLoadedFunc = function() {
			if (domLoaded) { return; }

			gadgets.util.runOnLoadHandlers();
			domLoaded = true;
		};

	/**
	 * Realization of DOMContentLoaded from jquery, needed to trigger runOnLoadHandlers function
	 */
	function bindDOMContentLoaded() {
		// Catch cases where $(document).ready() is called after the
		// browser event has already occurred.
		if ( document.readyState === "complete" ) {
			// Handle it asynchronously to allow scripts the opportunity to delay ready
			return setTimeout( domLoadedFunc, 1 );
		}

		// Mozilla, Opera and webkit nightlies currently support this event
		if ( document.addEventListener ) {
			// Use the handy event callback
			document.addEventListener( "DOMContentLoaded", domLoadedFunc, false );

			// A fallback to window.onload, that will always work
			window.addEventListener( "load", domLoadedFunc, false );

		// If IE event model is used
		} else if ( document.attachEvent ) {
			// ensure firing before onload,
			// maybe late but safe also for iframes
			document.attachEvent( "onreadystatechange", domLoadedFunc );

			// A fallback to window.onload, that will always work
			window.attachEvent( "onload", domLoadedFunc );
		}
	}

	bindDOMContentLoaded();
})();

