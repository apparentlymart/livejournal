Profile =
{
	init: function ($)
	{
		Profile.wishInit();
		
		// login user
		if (Site.has_remote) {
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
		}
		
		// add event listeners to all of the headers
		$('.expandcollapse').click(function(){ Profile.expandCollapse(this.id.replace('_header', ''), Site.has_remote) });
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
	},
	
	wishInit: function ()
	{
		var wishes_list = $('wishes_list'),
			viewport_width = wishes_list.parentNode.offsetWidth,
			container_width = wishes_list.lastChild.previousSibling.offsetLeft + wishes_list.lastChild.previousSibling.offsetWidth;
		if (container_width >= viewport_width) {
			var items = wishes_list.getElementsByTagName('li'),
				pages = [];
			for (var i=0; i < items.length; i++) {
				var left_widht = items[i].offsetLeft + items[i].offsetWidth;
				if (left_widht > viewport_width) {
					items[i].style.display = 'none';
				}
				var num_page = Math.floor(left_widht/viewport_width);
				if (!pages[num_page]) {
					pages[num_page] = [];
				}
				pages[num_page].push(items[i])
			}
			
			var nav = jQuery('#wishes_body .i-nav'),
				next = nav.find('.i-nav-next'),
				prev = nav.find('.i-nav-prev'),
				current = 0,
				go_next = function ()
				{
					if (pages[current + 1]) {
						prev.removeClass('i-nav-prev-dis');
						jQuery(pages[current]).hide();
						jQuery(pages[++current]).show();
						!pages[current + 1] && next.addClass('i-nav-next-dis');
					}
				},
				go_prev = function ()
				{
					if (pages[current - 1]) {
						next.removeClass('i-nav-next-dis');
						jQuery(pages[current]).hide();
						jQuery(pages[--current]).show();
						!pages[current - 1] && prev.addClass('i-nav-prev-dis');
					}
				};
			next.click(go_next)
			prev.click(go_prev)
			nav.show();
		}
		
		// recalc wish list on resize
		var timeout;
		jQuery(window).resize(function()
		{
			clearTimeout(timeout);
			timeout = setTimeout(function()
			{
				// restore to default state
				var nav = jQuery('#wishes_body .i-nav').hide();
				nav.find('.i-nav-next').unbind().removeClass('i-nav-next-dis');
				nav.find('.i-nav-prev').unbind().addClass('i-nav-prev-dis');
				jQuery("#wishes_list li").css('display', 'block');

				Profile.wishInit();
			}, 200);
		});
	}
}

jQuery(Profile.init);
