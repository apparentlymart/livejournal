Settings =
{
	confirm_msg: 'Save your changes?',
	form_changed: false,

	init: function($)
	{
		if (!$('#settings_form').length) {
			return;
		}
		// delegate onclick on all links to confirm form saving
		$({selector: 'a', context: document}).live('click', Settings.navclick_save);
		
		$({selector:'select, input, textarea', context: $('#settings_form')}).live('change', function()
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
		confirmed && $('settings_form').submit();
	}
}

jQuery(Settings.init);
