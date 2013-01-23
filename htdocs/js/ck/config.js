CKEDITOR.editorConfig = function(config) {
    'use strict';

    var isIE = jQuery.browser.msie;

    var extraPlugins,
        pluginName;

    if (Site.page.ljpost) {
        extraPlugins = {
            'livejournal': 'plugins/livejournal/plugin.js'  ,
            'ljcolor'    : 'plugins/lj/ljcolor/plugin.js'   ,
            'ljlink'     : 'plugins/lj/ljlink/plugin.js'    ,
            'ljfont'     : 'plugins/lj/ljfont/plugin.js'    ,
            'ljcut'      : 'plugins/lj/ljcut/plugin.js'     ,
            'ljuser2'    : 'plugins/lj/ljuser/plugin.js'    ,
            'ljembed'    : 'plugins/lj/ljembed/plugin.js'   ,
            'ljautogrow' : 'plugins/lj/ljautogrow/plugin.js',
            'ljlike'     : 'plugins/lj/ljlike/plugin.js'    ,
            'ljpoll'     : 'plugins/lj/ljpoll/plugin.js'    ,
            'ljimage'    : 'plugins/lj/ljimage/plugin.js'
        };

        if (isIE) {
            extraPlugins['ljspell'] = 'plugins/ljspell/plugin.js';
        }
    } else {
        extraPlugins = {
            'livejournal_old': 'plugins/livejournal_old/plugin.js'
        };
    }

    for (pluginName in extraPlugins) {
        CKEDITOR.plugins.addExternal(pluginName, extraPlugins[pluginName]);
    }

    var plugins = [
        'ajax',
        'basicstyles',
        'bidi',
        'blockquote',
        'button',
        'colorbutton',
        'colordialog',
        'enterkey',
        'entities',
        'format',
        'htmldataprocessor',
        'keystrokes',
        'list',
        'liststyle',
        'pastefromword',
        'specialchar',
        'tab',
        'toolbar',
        'undo',
        'wysiwygarea',
        'onchange'
    ];

    if (!Site.page.ljpost) {
        plugins.push('dialog', 'image', 'link', 'font');
    }

    /* Livejournal files on dev servers should be loaded as external plugins */
    config.extraPlugins = Object.keys(extraPlugins).join(',');
    if (Site.is_dev_server) {
        console.warn('Development server, loading plugins as external files');
        for (pluginName in extraPlugins) {
            delete CKEDITOR.plugins.registered[pluginName];
            CKEDITOR.plugins.addExternal(pluginName, extraPlugins[pluginName]);
        }
    }
    config.plugins = plugins.join(',');

    config.language = 'en';
    config.defaultLanguage = 'en';

    config.autoParagraph = false;
    config.autoUpdateElement = false;
    config.docType = '<!DOCTYPE html>';

    if (Site.page.ljpost) {
        config.contentsCss = Site.statprefix + '/js/ck/contents_new.css?t=' + Site.version;
        config.styleText = Site.statprefix + '/js/ck/contents_new.css?t=' + Site.version;
        config.bodyClass = 'lj-main-body';
    } else {
        config.contentsCss = '/js/ck/contents.css?t=' + Site.version;
        config.styleText = Site.statprefix + '/js/ck/contents.css?t=' + Site.version;
    }

    config.contentsLangDirection = 'ltr';
    config.fillEmptyBlocks = false;
    config.tabIndex = 41;
    config.tabSpaces = 2;
    config.startupShowBorders = false;
    config.toolbarCanCollapse = false;

    config.disableNativeSpellChecker = isIE ? true : false;

    var toolbar = [];

    function ifEnabled(condition, what) {
        return condition ? what : undefined;
    }

    if (Site.page.ljpost) {
        toolbar = [
            'Bold', 'Italic', 'Underline', 'Strike', 'LJFont', 'LJColor',

            '-',

            'LJLink2', 'LJUser2',

            '-',

            'LJImage',
            ifEnabled(Site.media_embed_enabled, 'LJEmbedLink'),

            'LJCut',
            'LJSpoiler',

            'LJMap',
            'LJLike',

            'LJPollLink',
            'NumberedList',
            'BulletedList',

            'LJJustifyLeft',
            'LJJustifyCenter',
            'LJJustifyRight',

            'LJSpell',

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

        [ CKEDITOR.CTRL + 76 /*L*/, 'LJLink2' ],

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

    config.LJFontDefault = 'normal';

    config.LJFontStyle = {
        element: 'span',
        styles: { 'font-size' : '#(size)' },
        overrides: [ { element : 'font', attributes : { 'size' : null } } ]
    };

    config.LJFontSize = {
        tiny: '0.7em',
        small: '0.9em',
        normal: '1.0em',
        large: '1.4em',
        huge: '1.8em'
    };

    config.protectedSource.push(/<lj-replace name="first_post"\s*\/?>/gi);
};

if (!Site.is_dev_server) {
    CKEDITOR.editorConfig(CKEDITOR.config);
}
