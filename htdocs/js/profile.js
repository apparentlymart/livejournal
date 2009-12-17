Profile =
{
	init: function ($)
	{
		// login user
		if (!Site.has_remote) {
			return;
		}
		// collapse any section that the user has set to collapse
		$.getJSON(
			LiveJournal.getAjaxUrl('profileexpandcollapse'),
			{ mode: 'load' },
			function(data)
			{
				$(data.headers).each(function()
				{
					document.getElementById(this + '_header') &&
						Profile.expandCollapse(this, false);
				});
			}
		);
		
		// add event listeners to all of the headers
		$('.expandcollapse').click(function(){ Profile.expandCollapse(this.id.replace('_header', ''), true) });
	},
	
	expandCollapse: function (id, should_save)
	{
		var headerid = id + '_header',
			body = $(id + '_body'),
			arrowid = id + '_arrow',
			expand = !DOM.hasClassName($(headerid), 'on');
		
		if (expand) {
			DOM.addClassName($(headerid), 'on');
			$(arrowid).src = Site.imgprefix + '/profile_icons/arrow-down.gif';
			body && (body.style.display = 'block');
		} else { // collapse
			DOM.removeClassName($(headerid), 'on');
			$(arrowid).src = Site.imgprefix + '/profile_icons/arrow-right.gif';
			body && (body.style.display = 'none');
		}
		
		// save the user's expand/collapse status
		if (should_save) {
			jQuery.get(
				LiveJournal.getAjaxUrl('profileexpandcollapse'),
				{ mode: 'save', header: headerid, expand: expand }
			);
		}
	}
}

jQuery(Profile.init);
