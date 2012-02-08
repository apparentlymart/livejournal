Profile =
{
	init: function ($)
	{
		var wishes_container = window.$("wishes_body"),
			wishes_list = window.$("wishes_list");
		if (wishes_container && wishes_list) {
			var nav = Profile.wishInit(wishes_container, wishes_list);
			Profile.navRecalculate = nav.recalculate;
		}

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
	},
	
	expandCollapse: function (id, should_save)
	{
		var headerid = id + '_header',
			body = $(id + '_body'),
			arrowid = id + '_arrow',
			expand = !DOM.hasClassName($(headerid), 'on');
		
		if (expand) {
			DOM.addClassName($(headerid), 'on');
			$(arrowid).src = Site.imgprefix + '/profile_icons/arrow-down.gif?v=14408';
			body && (body.style.display = 'block');
		} else { // collapse
			DOM.removeClassName($(headerid), 'on');
			$(arrowid).src = Site.imgprefix + '/profile_icons/arrow-right.gif?v=14408';
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
	
	navRecalculate: jQuery.noop,
	
	wishInit: function(nav_container, list) {
		// structure: <p class="i-nav"><i class="i-nav-prev i-nav-prev-dis"></i><span class="i-nav-counter"></span><i class="i-nav-next"></i></p>
		var current = 0,
			ITEM_WIDTH = 140,
			pages = [],
		
			nav = jQuery("<p/>", {
				"class": "i-nav"
			}),
			
			prev = jQuery("<i/>", {
				"class": "i-nav-prev i-nav-prev-dis",
				click: function() {
					if (pages[current - 1]) {
						next.removeClass("i-nav-next-dis");
						jQuery(pages[current]).hide();
						jQuery(pages[--current]).show();
						!pages[current - 1] && prev.addClass("i-nav-prev-dis");
						pager.text((current + 1) + "/" + pages.length);
					}
				}
			}).appendTo(nav),
			
			pager = jQuery("<span/>", {
				"class": "i-nav-counter"
			}, jQuery("div")).appendTo(nav),
			
			next = jQuery("<i/>", {
				"class": "i-nav-next",
				click: function() {
					if (pages[current + 1]) {
						prev.removeClass("i-nav-prev-dis");
						jQuery(pages[current]).hide();
						jQuery(pages[++current]).show();
						!pages[current + 1] && next.addClass("i-nav-next-dis");
						pager.text((current + 1) + "/" + pages.length);
					}
				}
			}).appendTo(nav);

		nav.appendTo(nav_container);

		function calculate() {
			var items = list.getElementsByTagName("li");
			if (items.length < 2) {
				return;
			}

			var viewport_width = list.parentNode.offsetWidth,
				container_width = items[items.length-1].offsetLeft + items[items.length-1].offsetWidth;

			if (container_width >= viewport_width) {
				var count_on_page = Math.floor(viewport_width/ITEM_WIDTH) || 1;
				for (var i=-1, item; item = items[++i]; ) {
					var num_page = Math.floor(i/count_on_page);

					if (num_page !== 0) {
						item.style.display = "none";
					}

					if (!pages[num_page]) {
						pages[num_page] = [];
					}
					pages[num_page].push(item);
				}

				pager.text(1 + "/" + pages.length);
				nav.show();
			}
		}

		function recalculate() {
			// restore to default state
			jQuery(list.getElementsByTagName("li")).css("display", "block");
			nav.hide();
			current = 0;
			pages = [];
			next.removeClass("i-nav-next-dis");
			prev.addClass("i-nav-prev-dis");

			calculate();
		}

		calculate();

		// recalc wish list on resize
		var timeout;
		function resize() {
			clearTimeout(timeout);
			timeout = setTimeout(recalculate, 200);
		}

		jQuery(window).resize(resize);

		return {
			recalculate: recalculate
		};
	}
};

jQuery(Profile.init);

// add event listeners to all of the headers
jQuery(document).delegate(".expandcollapse", "click", function() {
	Profile.expandCollapse(this.id.replace("_header", ""), Site.has_remote);

	if (this.id === "wishes_header" && / on$/.test(this.className)) {
		Profile.navRecalculate();
	}
});
