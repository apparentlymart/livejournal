/*
 Copyright (c) 2003-2011, CKSource - Frederico Knabben. All rights reserved.
 For licensing, see LICENSE.html or http://ckeditor.com/license
 */

CKEDITOR.editorConfig = function(config){
	config.language = 'ru';
	config.autoParagraph = false;
	config.autoUpdateElement = false;
	config.customConfig = '';
	config.docType = '<!DOCTYPE html>';
	config.baseHref = '';
	config.contentsCss = '/js/ck/contents.css';
	config.plugins =
		'basicstyles,' +
		'bidi,' +
		'blockquote,' +
		'button,' +
		'clipboard,' +
		'colorbutton,' +
		'colordialog,' +
		'dialog,' +
		'enterkey,' +
		'entities,' +
		'font,' +
		'format,' +
		'htmldataprocessor,' +
		'image,' +
		'keystrokes,' +
		'link,' +
		'list,' +
		'liststyle,' +
		'pastefromword,' +
		'specialchar,' +
		'tab,' +
		'toolbar,' +
		'undo,' +
		'wysiwygarea,';

	if(jQuery.browser.msie) { //show context menu only in internet explorer as it was in previous version of editor
		config.plugins += 'contextmenu,';
	}

	config.fullPage = false;
	config.startupOutlineBlocks = false;
	config.autoGrow_maxHeight = 400;
	config.defaultLanguage = 'en';
	config.contentsLangDirection = 'ltr';
	config.entities = true;
	config.entities_additional = '#39';
	config.entities_greek = true;
	config.entities_latin = true;
	config.enableTabKeyTools = true;
	config.fillEmptyBlocks = false;
	config.startupFocus = false;
	config.forcePasteAsPlainText = false;
	config.forceSimpleAmpersand = false;
	config.tabIndex = 1;
	config.tabSpaces = 2;
	config.startupShowBorders = false;
	config.toolbarStartupExpanded = true;
	config.toolbarCanCollapse = false;
	config.ignoreEmptyParagraph = true;
	config.baseFloatZIndex = 10000;
	config.htmlEncodeOutput = false;
	config.templates_replaceContent = true;
	config.toolbarLocation = 'top';
	config.toolbar_Full = [
		['Bold',
			'Italic',
			'Underline',
			'Strike',
			'TextColor',
			'FontSize',
			'-',
			'LJLink',
			'LJUserLink',
			'LJImage']
	];

	if(top.Site.media_embed_enabled){
		config.toolbar_Full[0].push('LJEmbedLink');
	}

	config.toolbar_Full[0].push('LJPollLink',
		'LJCutLink',
		'LJCut',
		'LJLike',
		'-',
		'UnorderedList',
		'OrderedList',
		'NumberedList',
		'BulletedList',
		'-',
		'JustifyLeft',
		'JustifyCenter',
		'JustifyRight',
		'-',
		'Undo',
		'Redo');

	config.toolbar = 'Full';
	config.enterMode = CKEDITOR.ENTER_BR;
	config.forceEnterMode = true;
	config.shiftEnterMode = CKEDITOR.ENTER_P;

	config.keystrokes = [
    [ CKEDITOR.ALT + 121 /*F10*/, 'toolbarFocus' ],
    [ CKEDITOR.ALT + 122 /*F11*/, 'elementsPathFocus' ],

    [ CKEDITOR.SHIFT + 121 /*F10*/, 'contextMenu' ],

    [ CKEDITOR.CTRL + 90 /*Z*/, 'undo' ],
    [ CKEDITOR.CTRL + 89 /*Y*/, 'redo' ],
    [ CKEDITOR.CTRL + CKEDITOR.SHIFT + 90 /*Z*/, 'redo' ],

    [ CKEDITOR.CTRL + 76 /*L*/, 'link' ],

    [ CKEDITOR.CTRL + 66 /*B*/, 'bold' ],
    [ CKEDITOR.CTRL + 73 /*I*/, 'italic' ],
    [ CKEDITOR.CTRL + 85 /*U*/, 'underline' ]
];

	config.browserContextMenuOnCtrl = true;
	config.colorButton_colors = '000000,993300,333300,003300,003366,000080,333399,333333,800000,FF6600,808000,808080,008080,0000FF,666699,808080,FF0000,FF9900,99CC00,339966,33CCCC,3366FF,800080,999999,FF00FF,FFCC00,FFFF00,00FF00,00FFFF,00CCFF,993366,C0C0C0,FF99CC,FFCC99,FFFF99,CCFFCC,CCFFFF,99CCFF,CC99FF,FFFFFF';
	config.fontSize_sizes = 'smaller;larger;xx-small;x-small;small;medium;large;x-large;xx-large';
	config.disableObjectResizing = true;
	config.disableNativeTableHandles = true;
	config.format_tags = 'p;h1;h2;h3;h4;h5;h6;pre;address;div';
	config.bodyId = '';
	config.bodyClass = '';
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
	config.indentUnit = 'px';

	config.dialog_backgroundCoverColor = '#ffffff';
	config.dialog_backgroundCoverOpacity = 0.50;

	config.extraPlugins = 'livejournal';
	config.protectedSource.push(/<lj-poll-\d+\s*\/?>/gi); // created lj polls;
	config.protectedSource.push(/<lj-replace name="first_post"\s*\/?>/gi);
	//config.protectedSource.push(/<lj-repost\s*\/?>/gi);

};
