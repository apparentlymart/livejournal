jQuery(function() {
	var entries = jQuery(".entry");
    
    function getCurrentEntry() {
        var scrollTop = jQuery(window).scrollTop();
        for (var i=0; i<entries.length; ++i) {
            // there is no exact equality between offset and scrollTop after call to scrollTo:
            // there may be offset=180.1, scrollTop=180
            //alert(entries.eq(i).offset().top + ", " + scrollTop);
            if (entries.eq(i).offset().top-20 > scrollTop) {
                return i-1;
            }
        }
        return -1;
    }

	function keyCheck(e) {
		if (!entries.length) {
			return;
		}

		var pos;
		if (e.keyCode === 78) {
			// next
            var anchor = getCurrentEntry()+1;
			if (anchor >= entries.length) {
				anchor=0;
			}
			pos = entries.eq(anchor).offset();
			window.scrollTo(pos.left, pos.top-10);
		}
		if (e.keyCode === 80) {
			//previous
			var anchor = getCurrentEntry()-1;
			if (anchor < 0) {
				anchor = entries.length-1;
			}
			pos = entries.eq(anchor).offset();
			window.scrollTo(pos.left, pos.top-10);
		}
	}

	jQuery(document).keyup(keyCheck);
});
