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