/*
 Copyright (c) 2003-2011, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.html or http://ckeditor.com/license
 */

CKEDITOR.editorConfig = function(config) {
	config.language = 'ru';
	config.autoParagraph = false;
	config.autoUpdateElement = false;
	config.docType = '<!DOCTYPE html>';
	config.contentsCss = '/js/ck/contents.css?t=' + Site.version;

	config.plugins = [
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
		'link',
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
		'livejournal'
	].join(',');

	if (jQuery.browser.msie || jQuery.browser.opera) { //show context menu only in internet explorer as it was in previous version of editor
		config.plugins += ',contextmenu';
	}
	config.autoGrow_maxHeight = 400;
	config.contentsLangDirection = 'ltr';
	config.fillEmptyBlocks = false;
	config.tabIndex = 1;
	config.tabSpaces = 2;
	config.startupShowBorders = false;
	config.toolbarCanCollapse = false;
	config.disableNativeSpellChecker = false;
	config.toolbar_Full = [
		[
			'Bold',
			'Italic',
			'Underline',
			'Strike',
			'TextColor',
			'FontSize',
			'-',
			'LJLink',
			'LJUserLink',
			'image'
		]
	];

	// if (window.ljphotoEnabled) {
	// 	config.toolbar_Full[0].push('LJImage_beta');
	// }

	if (top.Site.media_embed_enabled) {
		config.toolbar_Full[0].push('LJEmbedLink');
	}

	config.toolbar_Full[0].push('LJPollLink',
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
		'Redo');

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

	//config.extraPlugins = 'livejournal';
	config.protectedSource.push(/<lj-poll-\d+\s*\/?>/gi); // created lj polls;
	config.protectedSource.push(/<lj-replace name="first_post"\s*\/?>/gi);
};


CKEDITOR.editorConfig(CKEDITOR.config);