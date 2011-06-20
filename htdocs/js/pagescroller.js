jQuery(function() {
	var entries = jQuery(".entry");
    
    function getCurrentEntry() {
        var scrollTop = jQuery(window).scrollTop();
        for (var i=0; i<entries.length; ++i) {
            // there is no exact equality between offset and scrollTop after call to scrollTo:
            // there may be offset=180.1, scrollTop=180
            // console.log("entry=" + i + ", entries.eq(i).offset().top=" + entries.eq(i).offset().top + ", scrollTop=" + scrollTop);
            if (entries.eq(i).offset().top-20 > scrollTop) {
                return i-1;
            }
        }
        return entries.length-1;
    }

	function keyCheck(e) {

    	if (!entries.length) {
            // console.log("No entries");
			return;
		}

        // do not mess with form inputs
        var activeElement = document.activeElement;
        if (activeElement) {
            var nodeName = activeElement.nodeName.toLowerCase();
            if (nodeName=="input" || nodeName=="textarea" || nodeName=="select") {
                // console.log("returning from form element: " + nodeName);
                return;
            }
        }
        // console.log("Key code = " + e.keyCode);

		var pos;
		if (e.keyCode === 78) {
			// next
            var anchor = getCurrentEntry()+1;
            // console.log("next, anchor=" + anchor + ", entries.length=" + entries.length);
			if (anchor >= entries.length) {
				return;
			}
			pos = entries.eq(anchor).offset();
			window.scrollTo(pos.left, pos.top-10);
		}
		if (e.keyCode === 80) {
			//previous
			var anchor = getCurrentEntry()-1;
            // console.log("prev, anchor=" + anchor + ", entries.length=" + entries.length);
			if (anchor < 0) {
                return; 
			}
			pos = entries.eq(anchor).offset();
			window.scrollTo(pos.left, pos.top-10);
		}
	}

    if (entries.length>1) {
        // console.log("Installing keyCheck");
	    jQuery(document).keyup(keyCheck);
    }
});
