Settings =
{
	confirm_msg: 'Save your changes?',
	form_changed: false,

	init: function($)
	{
		Settings.$form = $('#settings_form');
		if (!Settings.$form.length) {
			return;
		}
		// delegate onclick on all links to confirm form saving
		$(document).delegate('a', 'click', Settings.navclick_save);
		
		Settings.$form.delegate('select, input, textarea', 'change', function()
		{
			Settings.form_changed = true;
		});
	},
	
	navclick_save: function(e)
	{
		if (!Settings.form_changed || e.isDefaultPrevented()) {
			return;
		}
		
		var confirmed = confirm(Settings.confirm_msg);
		confirmed && Settings.$form.submit();
	}
}

var applicationPageToggling = function ($) {
	$('.b-settings-apps-item-name')
		.click(function () {
			$(this).parent().toggleClass('b-settings-apps-item-open');
		});
}

jQuery(Settings.init);
jQuery(applicationPageToggling);
