/*
 Copyright (c) 2003-2011, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.html or http://ckeditor.com/license
 */

CKEDITOR.editorConfig = function(config) {
	CKEDITOR.plugins.addExternal( 'ljcolor', 'plugins/lj/ljcolor/plugin.js' );
	CKEDITOR.plugins.addExternal( 'ljlink', 'plugins/lj/ljlink/plugin.js' );

	var ljplugins = [/*'ljspell', */ (Site.page.ljpost) ? 'livejournal' : 'livejournal_old', 'ljcolor', 'ljlink'],
		plugins = [
			'ajax',
			'basicstyles',
			'bidi',
			'blockquote',
			'button',
			'colorbutton',
			'colordialog',
			'dialog',
			'enterkey',
			'entities',
			'font',
			'format',
			'htmldataprocessor',
			'image',
			'keystrokes',
			'list',
			'liststyle',
			'pastefromword',
			'specialchar',
			'tab',
			'table',
			'toolbar',
			'undo',
			'wysiwygarea',
			'onchange',
			'link',
			'autogrow'
		];

	config.language = 'ru';
	config.autoParagraph = false;
	config.autoUpdateElement = false;
	config.docType = '<!DOCTYPE html>';
	config.contentsCss = '/js/ck/contents.css?t=' + Site.version;

	config.styleText = Site.statprefix + '/js/ck/contents.css?t=' + Site.version;

	//config.scayt_autoStartup = true;

	config.fillEmptyBlocks = false;

	/* Livejournal files on dev servers should be loaded as external plugins */
	if (Site.is_dev_server) {
		config.extraPlugins = ljplugins.join(',');
	} else {
		Array.prototype.push.apply(plugins, ljplugins);
	}

	config.plugins = plugins.join(',');

	if (jQuery.browser.msie || jQuery.browser.opera) { //show context menu only in internet explorer as it was in previous version of editor
		config.plugins += ',contextmenu';
	}

	config.contentsLangDirection = 'ltr';
	config.fillEmptyBlocks = false;
	config.tabIndex = 41;
	config.tabSpaces = 2;
	config.startupShowBorders = false;
	config.toolbarCanCollapse = false;
	config.disableNativeSpellChecker = false;
	
	var toolbar = [];

	function ifEnabled(condition, what) {
		return condition ? what : undefined;
	}

	if (Site.page.ljpost) {
		toolbar = [
			'Bold', 'Italic', 'Underline', 'Strike', 'FontSize', 'LJColor',

			'-',

			'LJLink2', 'LJUserLink',

			'-',

			'image',
			ifEnabled(Site.media_embed_enabled, 'LJEmbedLink'),

			'LJCut',
			'LJSpoiler',
			
			'LJLike',

			'LJPollLink',
			'NumberedList',
			'BulletedList',

			'LJJustifyLeft',
			'LJJustifyCenter',
			'LJJustifyRight',

			'Undo',
			'Redo'
		];
	} else {
		toolbar = [
			'Bold',
			'Italic',
			'Underline',
			'Strike',
			'TextColor',
			'FontSize',

			'-',

			'LJLink',
			'LJUserLink',
			'image',
			ifEnabled(Site.media_embed_enabled, 'LJEmbedLink'),

			'LJPollLink',
			'LJCutLink',
			'LJCut',
			'LJLike',
			'LJSpoiler',

			'-',

			'UnorderedList',
			'OrderedList',
			'NumberedList',
			'BulletedList',

			'-',

			'LJJustifyLeft',
			'LJJustifyCenter',
			'LJJustifyRight',

			'-',

			'Undo',
			'Redo'
		];
	}

	config.toolbar_Full = [
		toolbar.filter(function(el) { return el; })
	];

	config.enterMode = CKEDITOR.ENTER_BR;
	config.shiftEnterMode = CKEDITOR.ENTER_P;

	config.keystrokes = [
		[ CKEDITOR.SHIFT + 121 /*F10*/, 'contextMenu' ],

		[ CKEDITOR.CTRL + 90 /*Z*/, 'undo' ],
		[ CKEDITOR.CTRL + 89 /*Y*/, 'redo' ],
		[ CKEDITOR.CTRL + CKEDITOR.SHIFT + 90 /*Z*/, 'redo' ],

		[ CKEDITOR.CTRL + 76 /*L*/, 'link' ],

		[ CKEDITOR.CTRL + 66 /*B*/, 'bold' ],
		[ CKEDITOR.CTRL + 73 /*I*/, 'italic' ],
		[ CKEDITOR.CTRL + 85 /*U*/, 'underline' ]
	];

	config.colorButton_colors = '000000,993300,333300,003300,003366,000080,333399,333333,800000,FF6600,808000,808080,008080,0000FF,666699,808080,FF0000,FF9900,99CC00,339966,33CCCC,3366FF,800080,999999,FF00FF,FFCC00,FFFF00,00FF00,00FFFF,00CCFF,993366,C0C0C0,FF99CC,FFCC99,FFFF99,CCFFCC,CCFFFF,99CCFF,CC99FF,FFFFFF';
	config.fontSize_sizes = 'smaller;larger;xx-small;x-small;small;medium;large;x-large;xx-large';
	config.disableObjectResizing = true;
	config.format_tags = 'p;h1;h2;h3;h4;h5;h6;pre;address';
	config.removeFormatTags = 'b,big,code,del,dfn,em,font,i,ins,kbd,q,samp,small,span,strike,strong,sub,sup,tt,u,var';
	config.removeFormatAttributes = 'class,style,lang,width,height,align,hspace,valign';
	config.coreStyles_bold = {
		element: 'b',
		overrides: 'strong'
	};
	config.coreStyles_italic = {
		element: 'i',
		overrides:'em'
	};

	config.indentClasses = [];
	config.indentOffset = 0;

	config.pasteFromWordRemoveFontStyles = false;
	config.pasteFromWordRemoveStyles = false;

	if (!Site.page.ljpost) {
		config.protectedSource.push(/<lj-poll-\d+\s*\/?>/gi); // created lj polls;
	}
	
	config.protectedSource.push(/<lj-replace name="first_post"\s*\/?>/gi);
};

CKEDITOR.editorConfig(CKEDITOR.config);
