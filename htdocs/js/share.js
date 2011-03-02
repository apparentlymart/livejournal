;(function( window, $ ) {

var default_options = {
	services: {
		livejournal: {
			title: 'LiveJournal', bindLink: 'http://www.livejournal.com/update.bml?repost={url}'
		},
		facebook: {
			title: 'Facebook', bindLink: 'http://www.facebook.com/sharer.php?u={url}'
		},
		twitter: {
			title: 'Twitter', bindLink: 'http://twitter.com/share?url={url}&text={title}'
		},
		vkontakte: {
			title: 'Vkontakte', bindLink: 'http://vkontakte.ru/share.php?url={url}'
		},
		moimir: {
			title: 'Moi Mir', bindLink: 'http://connect.mail.ru/share?url={url}'
		},
		stumbleupon: {
			title: 'Stumbleupon', bindLink: 'http://www.stumbleupon.com/submit?url={url}'
		},
		digg: {
			title: 'Digg', bindLink: 'http://digg.com/submit?url={url}'
		},
		email: {
			title: 'E-mail', bindLink: 'http://api.addthis.com/oexchange/0.8/forward/email/offer?username=internal&url={url}'
		},
		tumblr: {
			title: 'Tumblr', bindLink: 'http://www.tumblr.com/share?v=3&u={url}'
		},
		odnoklassniki: {
			title: 'Odnoklassniki', bindLink: 'http://www.odnoklassniki.ru/dk?st.cmd=addShare&st.s=1&st._surl={url}'
		}
	},
	links: [ 'livejournal', 'facebook', 'twitter', 'vkontakte', 'odnoklassniki', 'moimir', 'email', 'digg', 'tumblr', 'stumbleupon' ]
};

var global_options = $.extend( true, {}, default_options );

window.LJShare = {};

window.LJShare.init = function( opts ) {
	if( opts ) {
		global_options.services = $.extend( true, {}, default_options.services, opts.services );
		global_options.links = opts.links || global_options.links;
	}
}

window.LJShare.link = function( opts ) {
	var defaults = {
		title: '',
		description: '',
		url: ''
	}

	var link = jQuery( 'a:last' ),
		url = link.attr( 'href' ),
		options = jQuery.extend( {}, defaults, { url: url } , opts ),
		dom;

	options.links = ( opts.links ) ? opts.links : global_options.links;


	function buildDom() {
		var list = jQuery( '<ul>', { "class": 'ljshare-service-list' } ),
			li, a, clickFunc;

		for( var i = 0; i < options.links.length; ++i ) {
			a = jQuery( '<a>' )
				.html( global_options.services[ options.links[i] ].title );

			global_options.services[ options.links[i] ].href = a;
			$( '<li>', { "class": 'ljshare-service-' + options.links[i] } )
				.append( a )
				.appendTo( list );
		}

		dom = $( '<div>', { 'class': 'ljshare-container' } ).css( {
			position: 'absolute',
			visibility: 'hidden'
		} ).append( list );
	}

	function injectDom() {
		dom.appendTo( $( document.body ) );
	}

	function bindControls() {
		dom.bind( 'click', function( ev ) {
			ev.stopPropagation();
		} );

		$( window ).bind( 'click', function( ev ) {
			togglePopup( false );
		} );

		for( var i = 0; i < options.links.length; ++i ) {
			_bindLink( global_options.services[ options.links[i] ] );
		}
	}

	function _bindLink( service ) {
		if( typeof service.bindLink === "string" ) {
			callback = function() {
				togglePopup( false );
				window.open( service.bindLink.replace( "{url}", encodeURIComponent( options.url ) )
																		.replace( "{title}", options.title ) );
			}
		} else {
			callback = service.bindLink;
		}
		service.href.click( callback );
	}

	function updatePopupPosition() {
		var linkPos = link.offset(),
			linkH = link.height(), linkW = link.width();

		var scrollOffset = ( window.scrollY !== undefined ) ? scrollY :
								( window.pageYOffset ) ? pageYOffset :
								(((t = document.documentElement) || (t = document.body.parentNode)) && typeof t.ScrollTop == 'number' ? t : document.body).ScrollTop;

		var upperSpace = linkPos.top - scrollOffset;
		var lowerSpace = $( window ).height() - upperSpace - linkH;
		var domH = dom.height(), domW = dom.width();

		var linkTop = linkPos.top, linkLeft = linkPos.left;

		if( lowerSpace < domH && upperSpace > domH ) {
			linkTop -= domH + 5;
		} else {
			linkTop += linkH + 5;
		}

		var windowW = $( window ).width();
		if( linkPos.left + domW > windowW ) {
			linkLeft = windowW - domW - 10;
		}

		dom.css( {
			left: linkLeft + "px",
			top: linkTop + "px"
		} );
	}

	function togglePopup( show ) {
		show = show || false;
		if( show ) {
			updatePopupPosition();
		}

		dom.css( 'visibility', ( show ) ? 'visible' : 'hidden' );
	}

	link.attr( 'href', 'javascript:void(0)' )
		.click( function( ev ) {
			if( !dom ) {
				buildDom();
				injectDom();
				bindControls();
			}

			togglePopup( true );
			ev.preventDefault();
			ev.stopPropagation();
		} );
}

} )( window, jQuery );
