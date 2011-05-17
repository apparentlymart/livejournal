ILikeThis = {
	dialog: jQuery(),
	
	dialogRemove: function()
	{
		this.dialog.remove();
		jQuery(document).unbind('click', this.document_click);
	},
	
	// inline click
	rate: function(e, node, itemid, username)
	{
		var click = node.onclick;
		node.onclick = function(){ return false }
		// has undorate node
		var action = jQuery('.i_like_this_'+itemid+' .i_like_this_already').remove().length ? 'undorate' : 'rate';
		jQuery(node).parent().removeClass('i_dont_like_this');
		
		jQuery.ajax({
			url: LiveJournal.getAjaxUrl('eventrate'),
			data: {
				action: action,
				journal: username,
				itemid: itemid
			},
			type: 'POST',
			dataType: 'json',
			complete: function()
			{
				node.onclick = click;
			},
			success: function(data)
			{
				if (data.status === 'OK') {
					var append_node = jQuery('.we_like_this_'+itemid+' span>span>span');
					if (!append_node.length) { // s1
						append_node = jQuery('.we_like_this_'+itemid);
					}
					append_node.text(data.total);
					if (action == 'rate') {
						var context = jQuery('.i_like_this_'+itemid).addClass('i_dont_like_this'),
							append_node = context.find('span>span>span');
						if (!append_node.length) { // s1
							append_node = jQuery(context);
						}
						append_node.append('<i class="i_like_this_already">/</i>');
					}
				}
			}
		});
		return false;
	},
	
	// inline click
	showList: function(e, node, itemid, username)
	{
		this.ajax && this.ajax.abort();
		
		this.ajax = jQuery.ajax({
			url: LiveJournal.getAjaxUrl('eventrate'),
			data: {
				action: 'list',
				journal: username,
				itemid: itemid,
				limit: 10
			},
			type: 'POST',
			dataType: 'json',
			success: function(data)
			{
				$node = jQuery(node);
				if (data.status === 'OK') {
					ILikeThis.dialog.remove();
					ILikeThis.dialog = jQuery('<div/>', {
						'class': 'b-popup b-popup-messagebox b-popup-ilikethis',
						css: {top: 0, visibility: 'hidden'},
						html: '<div class="b-popup-head">'
									+'<h4>'+data.ml_users_who_like_it+' ('+data.total+')</h4><i class="i-popup-close" onclick="ILikeThis.dialogRemove()"></i>'
								+'</div>'
								+'<div class="b-popup-content">'
									+'<p class="b-popup-we_like_this">'
										+data.result
									+'</p>'
								+'</div>'
								+(data.total > 10 ? '<div class="b-popup-footer">'
									+'<p><a href="'+Site.siteroot+'/alleventrates.bml?journal='+username+'&itemid='+itemid+'">'
										+data.ml_view_all
									+'</a></p>' : ''
								+'</div>')
					}).ljAddContextualPopup();
					
					ILikeThis.dialog.appendTo(document.body);
					
					//calc with viewport
					var ele_offset = $node.offset(),
						left = ele_offset.left,
						top = ele_offset.top + $node.height() + 0, // TODO: 4 is fix markup height
						$window = jQuery(window);
					
					left = Math.min(left,  $window.width() + $window.scrollLeft() - ILikeThis.dialog.outerWidth(true));
					top = Math.min(top, $window.height() + $window.scrollTop() - ILikeThis.dialog.outerHeight(true));
					
					jQuery(document).click(ILikeThis.document_click);
					
					ILikeThis.dialog.css({
						left: left,
						top: top,
						visibility: 'visible'
					});
					
					var append_node = jQuery('.we_like_this_'+itemid+' span>span>span');
					if (!append_node.length) { // s1
						append_node = jQuery('.we_like_this_'+itemid);
					}
					
					append_node.text(data.total);
				}
			}
		});
		
		return false;
	},
	
	document_click: function(e)
	{
		if (!jQuery(e.target).parents('.b-popup-ilikethis').length) {
			ILikeThis.dialogRemove();
		}
	}
}

DonateButton = {
	ml_confirm_message: null,
	have_tokens: null,
	lj_form_auth: null,

	donate: function(node, journal, id) {
		if (confirm(DonateButton.ml_confirm_message)) {
			jQuery.post(LiveJournal.getAjaxUrl('give_tokens') + '?journal=' + journal + '&id=' + id, {
				confirm: 1
			}, function(data) {
				jQuery(node).find('lj-button-c').text(data.donated_text);
			});
		}
	}
};

jQuery(document).delegate('a', 'click', function(e) {
	if (this.href && this.href.indexOf(Site.siteroot + '/give_tokens.bml?journal=') === 0) {
		var parsed_url = LiveJournal.parseGetArgs(this.href);
		DonateButton.donate(this, parsed_url.journal, parsed_url.id);
		e.preventDefault();
	}
});

FriendsTimes = {
	prev_page_start: null,

	init: function() {
		jQuery(function(){
			FriendsTimes.checkUnreaded({
				timeout: 5000
			});
			FriendsTimes.bindLoadMore({
				max_load: 4
			});
		});
	},

	checkUnreaded: function(conf) {
		setInterval(function() {
			jQuery.ajax({
				url: LiveJournal.getAjaxUrl("ft_unreaded"),
				data: {
					after: Site.server_time
				},
				dataType: "json",
				timeout: conf.timeout - 1,
				success: function(data) {
					if (+data.unreaded) {
						jQuery(".b-friendstimes-f5")
							.show()
							.find("b").text(data.unreaded);
					}
				}
			});
		}, conf.timeout);
	},

	bindLoadMore: function(conf) {
		var $window = jQuery(window),
			more_node = jQuery(".b-friendstimes-loading"),
			loaded_count = 0;
		function loading_more() {
			if ((more_node.offset().top + more_node.height()) <= ($window.scrollTop() + $window.height())) {
				$window.unbind("scroll", loading_more);
				var start_time = new Date();
				jQuery.ajax({
					url: LiveJournal.getAjaxUrl("ft_more"),
					data: {
						to: FriendsTimes.prev_page_start
					},
					dataType: "html",
					success: function(html) {
						// slow hide text, minimum 2sec
						setTimeout(function() {
							if (html) {
								loaded_count++;
								more_node.before(html);
								if (loaded_count < conf.max_load) {
									jQuery(".b-friendstimes-pages").remove();
									$window.scroll(loading_more);
								} else {
									jQuery(".b-friendstimes-pages").show();
									more_node.remove();
								}
							} else {
								more_node.remove();
							}
						}, Math.max(0, start_time - new Date() + 2000));
					},
					error: function() {
						// retry
						setTimeout(loading_more, 5000);
					}
				});
			}
		}

		$window.scroll(loading_more);
	}
};

jQuery(function($) {
	if ($("#friendstimes").length) {
		FriendsTimes.init();
	}
});

// Share at some S2 styles
jQuery(document).click(function(e)
{
	var a = e.target,
		href = a.href,
		args;
	if (href && !a.shareClickIgnore) {
		if (href.indexOf('http://www.facebook.com/sharer.php') === 0) {
			LJShare.entry({url: decodeURIComponent(LiveJournal.parseGetArgs(href).u)})
				.attach(a, "facebook");
			a.shareClickIgnore = true;
			jQuery(a).click();
			e.preventDefault();
		} else if (href.indexOf("http://twitter.com/share") === 0) {
			args = LiveJournal.parseGetArgs(href);
			LJShare.entry({
				url: decodeURIComponent(args.url),
				title: decodeURIComponent(args.text)
			}).attach(a, "twitter");
			a.shareClickIgnore = true;
			jQuery(a).click();
			e.preventDefault();
		} else if (href.indexOf("http://api.addthis.com/oexchange/0.8/forward/email") === 0) {
			args = LiveJournal.parseGetArgs(href);
			LJShare.entry({
				url: decodeURIComponent(args.url),
				title: decodeURIComponent(args.title)
			}).attach(a, "email");
			a.shareClickIgnore = true;
			jQuery(a).click();
			e.preventDefault();
		}
	}
});
