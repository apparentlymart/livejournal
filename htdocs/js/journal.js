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

		var width = 639;
		var height = 230;

		LJ.rpc.bind( function( ev ) {
			if( ev.origin && ev.origin != Site.siteroot ) {
				return;
			}

			if( ev.data && ev.data.message === "updateWallet" ) {
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
			LJ.rpc.initRecipient( h, popupUrl, location.href.replace( /#.*$/, '' ) );
		}, 0 );

		event.stopPropagation ? event.stopPropagation() : (event.cancelBubble=true);
		return false;
	}
};

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

(function() {
	var storage = {
		init: function() {
			this._store = window.sessionStorage && sessionStorage.getItem('placeholders') || '';
		},

		makeHash: function(link) {
			return ' ' + encodeURIComponent(link) + ' ';
		},

		inStorage: function(link) {
			return this._store.indexOf(this.makeHash(link)) !== -1;
		},

		addUrl: function(link) {
			if (!window.sessionStorage) { return; }
			if (this.inStorage(link)) { return; }

			this._store += this.makeHash(link);
			sessionStorage.setItem('placeholders', this._store);
		}
	};

	storage.init();

	var placeholders = {
		image: {
			selector: '.b-mediaplaceholder-photo',
			loading: 'b-mediaplaceholder-processing',
			init: function() {
				var self = this;
				doc.on('click', this.selector, function(ev) { 
					self.handler(this, ev);
				});
			},

			handler: function(el, html) {
				var im = new Image();

				im.onload = im.onerror = jQuery.delayedCallback(this.imgLoaded.bind(this, el, im), 500);
				im.src = el.href;
				el.className += ' ' + this.loading;

				storage.addUrl(el.href);
			},

			imgLoaded: function(el, image) {
				var img = jQuery('<img />').attr('src', image.src),
					$el = jQuery(el),
					href = $el.data('href'),
					imw = $el.data('width'),
					imh = $el.data('height');

				if (imw) { img.width(imw); }
				if (imh) { img.height(imh); }

				if (href && href.length > 0) {
					img = jQuery('<a>', { href: href }).append(img);
					$el.next('.b-mediaplaceholder-external').remove();
				}

				$el.replaceWith(img);
			}
		},

		video: {
			handler: function(link, html) {
				link.parentNode.replaceChild(jQuery(unescape(html))[0], link);
			}
		}
	};
	// use replaceChild for no blink scroll effect

	// Placeholder onclick event
	LiveJournal.placeholderClick = function(el, html) {
		var type = (html === 'image') ? html : 'video';

		placeholders[type].handler(el, html);
		return false;
	};

	LiveJournal.register_hook('page_load', function() {
		jQuery('.b-mediaplaceholder').each(function() {
			if(storage.inStorage(this.href)) {
				this.onclick.apply(this);
			}
		});
	});
})();

/**
 * this code initializes common properies for all widgets.
 * If it will become too large, it should be moved to the separate file
 */
(function() {
	widgets = [
		{
			type: 'collapsable',
			handler: function() {
				jQuery(document).on('click', '.appwidget-prop-collapsable', function(ev) {
					if (ev.target.className.indexOf('w-head-status-switch') !== -1) {
						var videoCollapes = ev.target.className.indexOf('collapse') !== -1,
							//widget will have class like appwidget-videoforhomepage where videoforhomepage is the widget id
							id = this.className.replace(/(?:.*?)appwidget-(\S+).*/, '$1-'),
							fullid = id + this.getAttribute('data-cid'),
							cookie = decodeURIComponent(Cookie('clpsd') || ''),
							cookie_ids = cookie ? cookie.split(':') : [];

						jQuery(this).toggleClass('appwidget-prop-collapsed', videoCollapes);

						var found = false;
						for (var i = 0; i < cookie_ids.length; ++i) {
							if (cookie_ids[i].indexOf(id) !== -1) {
								found = true;
								if (videoCollapes) {
									cookie_ids[i] = fullid;
								} else {
									cookie_ids.splice(i, 1);
								}
								break;
							}
						}

						if (!found && videoCollapes) {
							cookie_ids.push(fullid);
						}

						Cookie('clpsd', cookie_ids.length > 0 ? cookie_ids.join(':') : null, { domain: location.host, expires: 30 });
					}
				});
			}
		}
	];

	widgets.forEach(function(prop) { prop.handler(); });
})();


/**
* delayed like buttons loader
*/

(function() {
	var likePos = [];

	LiveJournal.register_hook('page_load', function() {
		
		likePos = jQuery('.lj-like').map(function() {
			return {
				el: this,
				top: jQuery(this).offset().top,
				init: false
			};
		}).toArray();

		fullInit();

		if (likePos.length > 0) jQuery(window).scroll(fullInit);
	});

	function fullInit() {
		if (likePos.length > 0) {
			
			var scrollTop = jQuery(window).scrollTop(),
				windowHeight = jQuery(window).height(),

				toInit = likePos.filter(function(like) {
					return (!like.init &&
							 like.top > scrollTop - 100 &&
							 like.top < scrollTop + windowHeight + 200);
				});

			toInit.forEach(function(like) {
				var jEl = jQuery(like.el),
					likeHtml = jEl.html();
				
				jEl.html(likeHtml.slice(4, -3)); // strip '<!--' and '-->'
				LiveJournal.parseLikeButtons(jEl);

				like.init = true;
			});
		}
	}
	
})();
