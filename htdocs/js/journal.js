
ILikeThis = {
	dialog: jQuery(),
	
	// inline click
	rate: function(e, node, itemid, username)
	{
		ILikeThis.dialog.remove();
		var click = node.onclick;
		node.onclick = null
		// has undorate node
		var action = jQuery('.i_like_this_already', node).remove().length ? 'undorate' : 'rate';
		
		jQuery.ajax({
			url: LiveJournal.getAjaxUrl('eventrate'),
			data: {
				action: action,
				journal: username,
				jitemid: itemid
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
					jQuery('.we_like_this span>span>span', node.parentNode.parentNode).text(data.total);
					if (action == 'rate') {
						jQuery('span>span>span', node).append('<i class="i_like_this_already">/</i>');
					}
				}
			}
		});
		return false;
	},
	
	// inline click
	showList: function(e, node, itemid, username)
	{
		ILikeThis.dialog.remove();
		this.ajax && this.ajax.abort();
		
		this.ajax = jQuery.ajax({
			url: LiveJournal.getAjaxUrl('eventrate'),
			data: {
				action: 'list',
				journal: username,
				jitemid: itemid,
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
						'class': 'b-popup b-popup-messagebox',
						css: {top: 0, visibility: 'hidden'},
						html: '<div class="b-popup-head">'
									+'<h4>'+data.ml_view_all+' ('+data.total+')</h4><i class="i-popup-close" onclick="ILikeThis.dialog.remove()"></i>'
								+'</div>'
								+'<div class="b-popup-content">'
									+'<p class="b-popup-we_like_this">'
										+data.result
									+'</p>'
								+'</div>'
								+(data.total > 10 ? '<div class="b-popup-footer">'
									+'<p><a href="'+Site.siteroot+'/alleventrates.bml?journal='+username+'&jitemid='+itemid+'">'
										+data.ml_users_who_like_it
									+'</a></p>' : ''
								+'</div>')
					});
					
					ILikeThis.dialog.appendTo(document.body);
					
					//calc with viewport
					var ele_offset = $node.offset(),
						left = ele_offset.left,
						top = ele_offset.top + $node.height() + 0, // TODO: 4 is fix markup height
						$window = jQuery(window);
					
					left = Math.min(left,  $window.width() + $window.scrollLeft() - ILikeThis.dialog.outerWidth(true));
					top = Math.min(top, $window.height() + $window.scrollTop() - ILikeThis.dialog.outerHeight(true));
					
					ILikeThis.dialog.css({
						left: left,
						top: top,
						visibility: 'visible'
					});
					
					jQuery('.we_like_this span>span>span', node.parentNode.parentNode).text(data.total);
				}
			}
		});
		
		return false;
	}
}
