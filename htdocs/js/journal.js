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
	buyMore: function(node, ml_message, event) {
		var bubble = jQuery(node).data("buyMoreCachedBubble");
		if (!bubble) {
			bubble = jQuery("<span>" + ml_message + "</span>").bubble({
				target: node
			});
			jQuery(node).data("buyMoreCachedBubble", bubble);
		}

		bubble.bubble("show");
		event.stopPropagation ? event.stopPropagation() : (event.cancelBubble=true);
		return false;
	},

	donate: function( link, url_data, event ) {
		var url = link.href,
			origin, h;

		var width = 640;
		var height = 290;

		jQuery.rpc.bind( function( ev ) {
			if( ev.origin && ev.origin != Site.siteroot ) {
				return;
			}

			if( ev.data === "updateWallet" ) {
				LiveJournal.run_hook( 'update_wallet_balance' );
				jQuery.getJSON( LiveJournal.getAjaxUrl( 'give_tokens' ) + "?" + url_data + "&mode=js", 
					function( result ) {
						if( result.html ) {
							$node = jQuery( link ).closest( '.lj-button' );
							$node.replaceWith( result.html );
						}
					} );
			}
		} );

		var popupUrl = url + ( url.indexOf( "?" ) === -1 ? "?" : "&" ) + 'usescheme=nonavigation';
		h = window.open( 'about:blank', 'donate' , 'toolbar=0,status=0,width=' + width + ',height=' + height + ',scrollbars=yes,resizable=yes');
		h.name = location.href.replace( /#.*$/, '' );

		setTimeout( function() {
			jQuery.rpc.initRecipient( h, popupUrl, location.href.replace( /#.*$/, '' ) );
		}, 0 );

		event.stopPropagation ? event.stopPropagation() : (event.cancelBubble=true);
		return false;
	}
};

(function() {
	var prev_page_start, have_prev, list;

	function getList( html ) {
		var answer = jQuery( html ),
			node = answer.find( '.b-friendstimes' );

		return node
			.add( answer.filter( 'script' ) );
	}

FriendsTimes = {
	initTime: +new Date(),

	init: function( node ) {
		prev_page_start = node.attr( 'data-prev-page-start' );
		have_prev = parseInt( node.attr( 'data-have-prev' ), 10 );
		list = node;

		FriendsTimes.checkUnreaded({
			timeout: 5000
		});

		if( have_prev ) {
			FriendsTimes.bindLoadMore({
				max_load: 4
			});
		}
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

	fetchContent: function( data, success, error ) {
		jQuery.ajax({
			url: LiveJournal.getAjaxUrl("ft_more"),
			data: data,
			dataType: "html",
			success: function(html) {
				if( html ) {
					var node = getList( html ),
						li = node.children(),
						scripts = node.filter( 'script' );

					success( node, li, scripts );
				} else {
					success;
				}
			},
			error: error
		});
	},

	/**
	 * Fetch new posts that have appeared since page load.
	 *    Function loads new posts with ajax if the user is on the first page and there are ten
	 *    or less new posts.
	 */
	fetchNew: function() {
		var blockFunction = false,
			content;

		function loadContent() {
			FriendsTimes.fetchContent( {
					boundary: list.attr( 'data-firstitem' )
				}, function( node, li, scripts ) {
					var newBoundary = node.attr( 'data-firstitem' ),
						newTs = +new Date();

					if( li.length ) {
						list.attr( 'data-firstitem', newBoundary );
						Site.server_time += Math.floor( ( newTs - FriendsTimes.initTime ) / 1000 );
						FriendsTimes.initTime = newTs;
						content = li.add( scripts );
					}
				} );
		}

		function renderContent() {
			if( !content ) { setTimeout( renderContent, 1000 ); return; }

			jQuery(".b-friendstimes-f5").hide();

			content
				.css( 'opacity', 0.01 )
				.prependTo( list );

			LiveJournal.parseLikeButtons();

			setTimeout( function() {
				if( jQuery.browser.msie && +jQuery.browser.version <= 8 ) {
					content
						.css( 'opacity', 1 )
					blockFunction = false;
					content = null;
				} else {
					content
						.animate( { opacity: 1 }, 300, function() {
							blockFunction = false;
							content = null;
						} );
				}
			}, 200 );
		}

		return function( event ) {
			if( blockFunction ) { return false; }

			var unreadNumber = +jQuery(".b-friendstimes-f5 b").text(),
				getArgs = LiveJournal.parseGetArgs( location.href );

			if( unreadNumber > 10  || !!getArgs.to ) {
				return;
			}

			blockFunction = true;
			var animateComplete = false;
			jQuery( 'body,html' ).animate( { scrollTop: 0 }, 300, function() {
				if( !animateComplete ) {
					renderContent();
					animateComplete = true;
				}
			} );
			loadContent();

			if( event ) {
				event = jQuery.event.fix( event );
				event.preventDefault();
				event.stopPropagation();
			}
		}
	}(),

	bindLoadMore: function(conf) {
		var $window = jQuery(window),
			more_node = jQuery(".b-friendstimes-loading"),
			loaded_count = 0;

		function loading_more() {
			// preload
			if ((jQuery(document).height() - 1000) <= ($window.scrollTop() + $window.height())) {
				$window.unbind("scroll", loading_more);
				FriendsTimes.fetchContent( { to: prev_page_start },
					function( node, li, scripts ) {
						if( li ) {
							list.append( li ).append( scripts );
							LiveJournal.parseLikeButtons();
							prev_page_start = node.attr( 'data-prev-page-start' );
							have_prev = parseInt( node.attr( 'data-have-prev' ), 10 );

							if (loaded_count < conf.max_load) {
								if( !have_prev ) {
									$window.scroll(loading_more);
								} else {
									more_node.remove();
								}
							} else {
								node.nextAll( '.b-friendstimes-pages' )
									.insertAfter( list )
									.show();
								more_node.remove();
							}
						} else {
							more_node.remove();
						}
					}, function() {
						// retry
						setTimeout(loading_more, 5000);
					} );
			}
		}

		$window.scroll(loading_more);
		loading_more();
	}
};

} )();

jQuery(function($) {
	var ft = $( '#friendstimes' )
	if ( ft.length) {
		FriendsTimes.init( ft.find( '.b-friendstimes' ) );
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

(function() {
	var options = {
		blockSelector: '.yota-contest'
	};

	function retrieveContestInfo( element ) {
		var journal = element.attr( 'data-user' );
		jQuery.getJSON( LiveJournal.getAjaxUrl( 'yota_widget_post' ),
						{ json: 1, journal: journal }, function( answer ) {
			if( 'collected' in answer ) {
				var collected = answer.collected;
				for( var i = 0; i < collected.length; i += 2 ) {
					element.find( "." + collected[ i ] ).html( collected[ i + 1 ] );
				}
			}

			if( 'rating' in answer ) {
				i = 5;
				var key;
				while( --i > 0) {
					key = "" + i;
					if( key in answer.rating ) {
						element.find( '.c' + i ).html( answer.rating[ key ] );
					}
				}
			}
		} );
	}

	function findElement() {
		var element = jQuery( options.blockSelector );

		if( element.length ) {
			element.each( function() {
				retrieveContestInfo( jQuery( this ) );
			} );
		}
	}

	jQuery( function() {
		findElement();
	} );
} )();
