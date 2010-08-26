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

// Share
SHARETHIS_ary = [];
SHARETHIS_ary.findByUrl = function(url)
{
	for (var i = this.length - 1; i >= 0; i--) {
		if (url === this[i].properties.url) {
			return this[i];
		}
	}
}

jQuery(document).click(function(e)
{
	// Share in Facebook
	var a = e.target,
		href = a.href;
	if (href) {
		if (href.indexOf('http://www.facebook.com/sharer.php') === 0) {
			a.setAttribute('st_dest', 'facebook.com');
			SHARETHIS_ary.findByUrl(decodeURIComponent(LiveJournal.parseGetArgs(href).u)).chicklet(e);
			//else? window.open(href, 'sharer', 'toolbar=0,status=0,width=626,height=436');
			e.preventDefault();
		} else if (href.indexOf(Site.siteroot + '/share/twitter.bml') === 0) {
			a.setAttribute('st_dest', 'twitter.com');
			SHARETHIS_ary.findByUrl(decodeURIComponent(LiveJournal.parseGetArgs(href).u)).chicklet(e);
			//else? window.open(href, 'sharer', 'toolbar=0,status=0,width=430,height=220');
			e.preventDefault();
		} else if (href.indexOf(Site.siteroot + '/tools/tellafriend.bml') === 0) {
			a.setAttribute('st_page', 'send');
			SHARETHIS_ary.findByUrl(decodeURIComponent(LiveJournal.parseGetArgs(href).u)).popup(e);
			e.preventDefault();
		}
	}
});
