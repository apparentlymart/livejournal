(function( window, $ ) {

/**
* 
* Livejournal sharing script.
* 
* Usage:
* 
* .. Somewhere in the head ..
* <script type="text/javascript">
* 	//show only three links in popup by default
* 	LJShare.init({"ml":{"close":"Close","title":"Share"},"links":["facebook","twitter","email"]})
* </script>
* 
* .. Somewhere on the page ..
* <a href="#">share</a>
* <script type="text/javascript">
* 	LJShare.link( {
* 		"url":"http://community.livejournal.com/news/750.html",
* 		"title":"Some title",
* 		"description":"Some description",
* 		"links": [ "twitter", "vkontakte", "moimir" ] //we want custom buttons there
* 	});
* </script>
* 
* 
*/

function preload( srcArr ) {
	for( var i = srcArr.length; --i;
		( new Image() ).src = srcArr[ i ] + '?' + Math.random() );
}

preload( [
	'/img/popup-cls.gif',
	'/img/popup-arr.gif',
	'/img/icons/sharethis.gif'
] );

function supplant(str, o) {
	return str.replace(/{([^{}]*)}/g,
		function (a, b) {
			var r = o[b];
			return typeof r === 'string' || typeof r === 'number' ? r : a;
		}
	);
}

var selectors = {
	close: ".i-popup-close",
	links: ".b-sharethis-services a",
	arrow: ".i-popup-arr"
};

// four arrow positions availible
var arrow_opts = {
	className: "i-popup-arr",
	position: {
		tl: "i-popup-arrtl",
		tr: "i-popup-arrtr",
		bl: "i-popup-arrbl",
		br: "i-popup-arrbr"
	}
};

var template = {
	//here we take values from global_options.ml object
	start: ' \
		<div class="b-sharethis b-popup"> \
			<div class="b-popup-outer"> \
				<div class="b-popup-inner"> \
					<div class="b-sharethis-head">{title}</div> \
					<div class="b-sharethis-services">',
	//here we take values from an object made from service object. Availible vars: name, url, title.
	item: '<span class="b-sharethis-{name}"><a href="{url}" target="_blank">{title}</a></span>',
	//here we take values from global_options.ml object
	end: '</div> \
				</div> \
				<i class="i-popup-arr i-popup-arrtl"></i><i class="i-popup-close" title="{close}"></i> \
			</div> \
		</div>'
};

//buildLink takes values passed to the url with link method ( title, post url, description )
var default_options = {
	ml: {
		close: "Close",
		title: "Share"
	},
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
	//list of links wich will be shown, when user will click on share link. Can be overriden in init and link methods.
	links: [ 'livejournal', 'facebook', 'twitter', 'vkontakte', 'odnoklassniki', 'moimir', 'email', 'digg', 'tumblr', 'stumbleupon' ]
};

var global_options = $.extend( true, {}, default_options );

window.LJShare = {};

/**
* Overrides default options for current page.
* 
* @param Object opts Options object, may contain the following fields:
*    ml - translation strings to use;
*    services - An Object, that contains configuration fields for services links;
*    links - array of links that will be shown to the user in popup.
*/
window.LJShare.init = function( opts ) {
	if( opts ) {
		global_options = $.extend( true, {}, default_options, opts );
		global_options.links = opts.links || global_options.links;
	}
}

/**
* Bind share popup to the latest link found on the page
* 
* @param Object opts Options object, may contain the following fields:
*    title, description, url - parameters of the page you want to share;
*    links - array of links that will be shown to the user in popup.
*/
window.LJShare.link = function( opts ) {
	var defaults = {
		title: '',
		description: '',
		url: ''
	}

	var link = jQuery( 'a:last' ),
		url = link.attr( 'href' ),
		options = jQuery.extend( {}, defaults, { url: url } , opts ),
		dom, arrow, skipCloseEvent;

	var links = ( opts.links ) ? opts.links : global_options.links;


	function buildDom() {
		var str = supplant( template.start, global_options.ml ),
			serviceName, serviceObj;

		for( var i = 0; i < links.length; ++i ) {
			serviceName = links[i];
			serviceObj = global_options.services[ serviceName ];

			str+= supplant( template.item, {
				name: serviceName,
				title: serviceObj.title, 
				url: supplant( serviceObj.bindLink, options )
			} );
		}

		str += supplant( template.end, global_options.ml );

		dom = $( str ).css( {
			position: 'absolute'
		} ).hide();
	}

	function injectDom() {
		dom.appendTo( $( document.body ) );
		arrow = dom.find( selectors.arrow );
	}

	function bindControls() {
		dom.bind( 'click', function( ev ) {
			ev.stopPropagation();
		} );

		function checkClose( e ) {
			if( !skipCloseEvent ) {
				togglePopup( false );
			}
			skipCloseEvent = false;
		}

		dom.find( selectors.close ).bind( 'click', function( ev ) {	togglePopup( false ); } );
		$( document ).bind( 'click', checkClose );
		$( window ).bind( 'resize', checkClose );
		dom.find( selectors.links ).click( function() { togglePopup( false ); } );
	}

	function updatePopupPosition() {
		var linkPos = link.offset(),
			linkH = link.height(), linkW = link.width(),
			arrPos = "";

		//we check if child elements of the link have bigger dimensions.
		link.find( '*' ).each( function() {
			var $this = $( this ),
				position = $this.css( 'position' ),
				height = $( this ).outerHeight();

			if( $this.is( ':visible' ) && position != 'absolute'
				&& position != 'fixed' && height > linkH ) {
				linkH = height;
			}
		} );

		dom.css( { left: "0px", top: "0px" } );

		var scrollOffset = $( window ).scrollTop();
		var upperSpace = linkPos.top - scrollOffset;
		var lowerSpace = $( window ).height() - upperSpace - linkH;
		var domH = dom.height(), domW = dom.width();

		var linkTop = Math.floor( linkPos.top ), linkLeft = Math.floor( linkPos.left );


		//we decide whether the popup should be shown under or above the link
		if( lowerSpace < domH && upperSpace > domH ) {
			linkTop -= domH + 9;
			arrPos += "b";
		} else {
			linkTop += linkH + 7;
			arrPos += "t";
		}

		//we decide whether the popup should positioned to the left or to the right from the link
		var windowW = $( window ).width();
		if( linkPos.left + domW > windowW ) {
			linkLeft = windowW - domW - 8;
			arrPos += "r";
		} else {
			arrPos += "l";
			linkLeft -= 25;
			if( linkW == 16 ) {
				linkLeft -= 4;
			}

		}

		arrow.removeClass().addClass( arrow_opts.className ).addClass( arrow_opts.position[ arrPos ] ); 

		dom.css( { left: linkLeft + "px",top: linkTop + "px" } );
	}

	function togglePopup( show ) {
		show = show || false;
		if( show ) {
			updatePopupPosition();
		}

		dom[ ( show ) ? 'show' : 'hide' ]();
	}

	link.attr( 'href', 'javascript:void(0)' )
		.click( function( ev ) {
			if( !dom ) {
				buildDom();
				injectDom();
				bindControls();
			}

			togglePopup( true );
			skipCloseEvent = true;
			ev.preventDefault();
		} );
}

} )( window, jQuery );
