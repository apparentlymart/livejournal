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
jQuery.fn.placeholder = function()
{
	if ('placeholder' in document.createElement('input')) {
		arguments.callee = function() { return this; }
	} else {
		arguments.callee = function()
		{
			var check_focus = function()
				{
					if (this.value === this.getAttribute('placeholder')) {
						jQuery(this)
							.val('')
							.removeClass('placeholder');
					}
				},
				check_blur = function()
				{
					if (!this.value) {
						jQuery(this)
							.val(this.getAttribute('placeholder'))
							.addClass('placeholder');
					}
				};
				
			this.each(function()
			{
				var $this = jQuery(this);
				
				$this.focus(check_focus).blur(check_blur);
				
				check_blur.apply(this);
				jQuery(this.form).submit(function()
				{
					$this.hasClass('placeholder') && $this.removeClass('placeholder').val('');
				});
			});
			return this;
		}
	}
	
	arguments.callee.apply(this, arguments);
	return this;
}

jQuery.fn.input = function(fn)
{
	return fn ? this.bind('input keyup paste', fn) : this.trigger('input');
}
