//= require js/core/template.js
//= require js/core/track.js
//= require js/core/widget.js

// This file contains general-purpose LJ code
var LiveJournal = {};

/**
* @deprecated Deprecated methods (for backward compatibility only)
*/
LiveJournal.register_hook = LJ.Event.on;
LiveJournal.remove_hook   = LJ.Event.off;
LiveJournal.run_hook      = LJ.Event.trigger;


LiveJournal.initPage = function () {
    //LJRU-3137: The code relies on the Site global variable
    //so it appears on all livejournal pages. If it's
    //not there than we are on the external site.
    if (!window.Site) {
        return;
    }

    // when page loads, set up contextual popups
    jQuery(ContextualPopup.setupLive);

    if (LJ.Api) {
        LJ.Api.init({ auth_token: Site.auth_token });
    }

    LJ.UI.bootstrap();

    //register system hooks
    LiveJournal.register_hook('update_wallet_balance', LiveJournal.updateWalletBalance);
    LiveJournal.register_hook('xdr/message', LiveJournal.processXdr);

    // set up various handlers for every page
    LiveJournal.initInboxUpdate();

    LiveJournal.initNotificationStream();
    LiveJournal.initSpoilers();
    LiveJournal.initResizeHelper();

    //ljuniq cookie is checked here now instead of PageStats/Omniture.pm
    LiveJournal.checkLjUniq();

    // run other hooks
    LiveJournal.run_hook('page_load');
};

/**
 * Special helper class is added to the body if browser doesn't support media queries and
 * screen width is less then 1000px.
 */
LiveJournal.initResizeHelper = function() {
    var $window = jQuery(window),
        $body = jQuery('body'),
        hasClass = false,
        resizeFunc = LJ.throttle(function() {
            if ($window.width() <= 1000) {
                if (!hasClass) {
                    $body.addClass('l-width1000');
                    hasClass = true;
                }
            } else if (hasClass) {
                $body.removeClass('l-width1000');
                hasClass = false;
            }
        }, 500);

    //Only older ies need thes (caniuse.com)
    if (jQuery.browser.msie && Number(jQuery.browser.version) <= 8) {
        $window.on('resize', resizeFunc);
        resizeFunc();
    }
};

/**
 * Spoilers functionality - expand hidden text in posts when user clicks on corresponding link
 */
LiveJournal.initSpoilers = function() {
    jQuery(document).delegate('.lj-spoiler > .lj-spoiler-head a', 'click', function (evt) {
        evt.preventDefault();
        jQuery(this).closest('.lj-spoiler').toggleClass('lj-spoiler-opened');
    });
};

/**
 * Init long-polling connection to the server.
 * Now function can be used for testing purposes and
 * should be modified for any real use. E.g. it could be
 * used as an adapter to the Socket.IO
 */
LiveJournal.initNotificationStream = function(force) {
    force = force || false;
    var abortNotifications = false, seed = Site.notifySeed || 0;

    if (Site.notifyDisabled || (!Cookie('ljnotify') && !force && (Math.random() > seed))) {
        return;
    }

    if (!Cookie('ljnotify')) {
        Cookie('ljnotify', '1', {
            domain: Site.siteroot.replace(/^https?:\/\/www\./, ''),
            expires: 5000,
            path: '/'
        });
    }

    LiveJournal.register_hook('notification.stop', function() {
        abortNotifications = true;
    });

    function requestRound() {
        if (abortNotifications) {
            return;
        }

        jQuery.get(LiveJournal.getAjaxUrl('notifications'), 'json').success(
            function(data) {
                //if it's not a notification than it is a timeout answer
                if (data.type === 'notification') {
                    LiveJournal.run_hook(data.name, data.params || []);
                }
                requestRound();
            }).error(function() {
                requestRound()
            });
    }

    requestRound();
};

/**
 * Translate message from xdreceiver. The function will eventually be run
 *      from xdreceiver.html helper frame to send messages between different domains.
 *
 * @param {Object} message Object with the message. Object should always contain type field with event name
 */
LiveJournal.processXdr = function(message) {
    if (message.type) {
        var type = decodeURIComponent(message.type);
    } else {
        return;
    }

    var messageCopy = {};
    for (var name in message) {
        if (message.hasOwnProperty(name) && name !== 'type') {
            messageCopy[name] = decodeURIComponent(message[name]);
        }
    }

    LiveJournal.run_hook(type, messageCopy);
};

// Set up a timer to keep the inbox count updated
LiveJournal.initInboxUpdate = function () {
    // Don't run if not logged in or this is disabled
    if (! Site || ! Site.has_remote || ! Site.inbox_update_poll) {
        return;
    }

    // Don't run if no inbox count
    if (!$('LJ_Inbox_Unread_Count')) {
        return;
    }

    // Update every five minutes
    window.setInterval(LiveJournal.updateInbox, 1000 * 60 * 5);
};

// Do AJAX request to find the number of unread items in the inbox
LiveJournal.updateInbox = function () {

    jQuery.post(LiveJournal.getAjaxUrl('esn_inbox'), {
        action: 'get_unread_items'
    }, function(resp) {
        if (! resp || resp.error) {
            return;
        }

        var unread = $('LJ_Inbox_Unread_Count');
        if (unread) {
            unread.innerHTML = resp.unread_count ? '  (' + resp.unread_count + ')' : '';
        } else {
            unread = $('LJ_Inbox_Unread_Count_Controlstrip');
            if (unread) {
                unread.innerHTML = resp.unread_count ? resp.unread_count : '0';
            }
        }
    }, 'json');
};

//refresh number of tokens in the header
LiveJournal.updateWalletBalance = function () {
    jQuery.get(LiveJournal.getAjaxUrl('get_balance'), function(resp) {
        if (! resp || resp.status != 'OK') {
            return;
        }
        var newBalance = resp.balance ? parseInt(resp.balance, 10) : 0;

        var balance = $('LJ_Wallet_Balance');
        if (balance) {
            if (resp.balance) {
                balance.innerHTML = balance.innerHTML.replace(/\d+/, newBalance);
            } else {
                balance.innerHTML = '';
            }
        } else {
            balance = $('LJ_Wallet_Balance_Controlstrip');
            if (balance) {
                balance.innerHTML = newBalance;
            }
        }

        LiveJournal.run_hook('balance_updated', resp.balance);
    }, 'json');
};

// handy utilities to create elements with just text in them
function _textSpan() {
    return _textElements('span', arguments);
}
function _textDiv() {
    return _textElements('div', arguments);
}

function _textElements(eleType, txts) {
    var ele = [];
    for (var i = 0; i < txts.length; i++) {
        var node = document.createElement(eleType);
        node.innerHTML = txts[i];
        ele.push(node);
    }

    return ele.length == 1 ? ele[0] : ele;
}

LiveJournal.pollAnswerClick = function(e, data) {
    if (!data.pollid || !data.pollqid) {
        return false;
    }

    var xhr = jQuery.post(LiveJournal.getAjaxUrl('poll'), {
        pollid   : data.pollid,
        pollqid  : data.pollqid,
        page         : data.page,
        pagesize : data.pagesize,
        action   : 'get_answers'
    }, function(data, status) {
        status == 'success' ? LiveJournal.pollAnswersReceived(data) : LiveJournal.ajaxError(data);
    }, 'json');

    jQuery(e).hourglass(xhr);

    return false;
};

LiveJournal.pollAnswersReceived = function(answers) {
    if (!answers || !answers.pollid || !answers.pollqid) {
        return;
    }

    if (answers.error) {
        return LiveJournal.ajaxError(answers.error);
    }

    var id = '#LJ_Poll_' + answers.pollid + '_' + answers.pollqid,
        to_remove = '.LJ_PollAnswerLink, .lj_pollanswer, .lj_pollanswer_paging',
        html = '<div class="lj_pollanswer">' + (answers.answer_html || '(No answers)') + '</div>';

    answers.paging_html && (html += '<div class="lj_pollanswer_paging">' + answers.paging_html + '</div>');

    jQuery(id)
        .find(to_remove)
        .remove()
        .end()
        .prepend(html)
        .find('.lj_pollanswer');
};

// gets a url for doing ajax requests
LiveJournal.getAjaxUrl = function(action, params) {
    // if we are on a journal subdomain then our url will be
    // /journalname/__rpc_action instead of /__rpc_action
    var uselang = LiveJournal.parseGetArgs(location.search).uselang;
    if (uselang) {
        action += '?uselang=' + uselang;
    }
    if (params) {
        action += (uselang ? '&' : '?') + jQuery.param(params);
    }

    return Site.currentJournal ? '/' + Site.currentJournal + '/__rpc_' + action : '/__rpc_' + action;
};

// generic handler for ajax errors
LiveJournal.ajaxError = function (err) {
    if (LJ_IPPU) {
        LJ_IPPU.showNote('Error: ' + err);
    } else {
        alert('Error: ' + err);
    }
};

// given a URL, parse out the GET args and return them in a hash
LiveJournal.parseGetArgs = function (url) {
    url = url || window.location.href;
    url = url.replace(/#.*$/, '');

    var getArgsHash = {};

    var urlParts = url.split('?');
    if (!urlParts[1]) {
        return getArgsHash;
    }
    var getArgs = urlParts[1].split('&');

    for (var arg = 0; arg < getArgs.length; arg++) {
        var pair = getArgs[arg].split('=');
        getArgsHash[pair[0]] = pair[1];

    }

    return getArgsHash;
};

/**
 * Construct an url from base string and params object.
 *
 * @param {String} base Base string.
 * @param {Object} args Object with arguments, that have to be passed with the url.
 * @return {String}
 */
LiveJournal.constructUrl = function(base, args, escapeArgs) {
    base = base.replace(/(\&|\?)+$/g, '');
    var queryStr = base,
        queryArr = [];

    if (args) {
        queryStr += ( base.indexOf('?') === -1 ? '?' : '&' );

        for (var i in args) {
            queryArr.push(i + '=' + ( ( escapeArgs ) ? encodeURIComponent(args[i]) : args[i] ));
        }
    }

    return queryStr + queryArr.join('&');
};

/**
 * Generate a string for ljuniq cookie
 *
 * @return {String}
 */
LiveJournal.generateLjUniq = function() {
    var alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', result = '', i;

    var len = 15;
    for (i = 0; i < len; ++i) {
        result += alpha.charAt(Math.floor(Math.random() * ( alpha.length - 1 )));
    }

    result += ':' + Math.floor((new Date()) / 1000);
    result += ':pgstats' + ( ( Math.random() < 0.05 ) ? '1' : '0' );

    return result;
};

LiveJournal.checkLjUniq = function() {
    if (!Cookie('ljuniq')) {
        Cookie('ljuniq', LiveJournal.generateLjUniq(), {
                domain: Site.siteroot.replace(/^https?:\/\/www\./, ''),
                expires: 5000,
                path: '/'
            });
    }
};

LiveJournal.closeSiteMessage = function(node, e, id) {
    jQuery.post(LiveJournal.getAjaxUrl('close_site_message'), {
        messageid: id
    }, function(data, status) {
        if (status === 'success') {
            jQuery(node.parentNode.parentNode.parentNode).replaceWith(data.substitude);
        } else {
            LiveJournal.ajaxError(data);
        }
    }, 'json');
};

LiveJournal.parseLikeButtons = (function () {
    'use strict';

    var selectors = {
        facebook: '.lj-like-item-facebook',
        google: '.lj-like-item-google',
        twitter: '.lj-like-item-twitter',
        tumblr: '.lj-like-item-tumblr',
        surfingbird: '.lj-like-item-surfinbird',
        repost: '.lj-like-item-repost'
    };

    /**
     * Parse lj-like buttons
     * @param  {Object} $node jQuery .lj-like node
     */
    function parse($node) {
        /**
         * Notice: tumblr button works through entry sharing
         */
        parseFacebook($node);
        parseGoogle($node);
        parseTwitter($node);
        parseSurfingbird($node);
        parseRepost($node);
    }

    /**
     * Create iframe node with default params and ability to redefine them (iframe factory)
     * @param  {Object} params Params to substitute for iframe {src, width, height...}
     * @return {Element}       Created iframe node
     */
    function createIframe(params) {
        var iframe = document.createElement('iframe'),
            param;

        // defaults
        iframe.frameBorder = 0;
        iframe.scrolling = 'no';
        iframe.allowTransparency = 'true';
        iframe.width = 110;
        iframe.height = 20;

        // reassign params
        if (params) {
            for (param in params) {
                if (params.hasOwnProperty(param)) {
                    iframe[param] = params[param];
                }
            }
        }

        return iframe;
    }

    /**
     * Parse facebook likes
     * Documentation: http://developers.facebook.com/docs/reference/javascript/FB.XFBML.parse/
     * @param  {jQuery} $node jQuery collection
     */
    function parseFacebook($node) {
        var item = $node.find( selectors.facebook );

        if (item.length === 0) {
            return;
        }

        try {
            window.FB.XFBML.parse( item.get(0) );
        } catch (e) {
            console.warn(e.message);
        }
    }

    /**
     * Parse google +1 button
     * Documentation: https://developers.google.com/+/plugins/+1button/#jsapi
     * @param  {jQuery} $node jQuery node with likes in which we will search for google +1 button for parsing
     */
    function parseGoogle($node) {
        var $button = $node.find( selectors.google ).children().first(),    // jquery node <g:plusone />
            button = null;  // raw DOM node <g:plusone>

        if ($button.length === 0) {
            return;
        }

        button = $button.get(0);

        // gapi could throw errors
        try {
            window.gapi.plusone.render( button, { size: $button.attr('size'), href: $button.attr('href') } );
        } catch (e) {
            console.warn(e.message);
        }
    }

    /**
     * Parse and replace twitter button
     * @param  {jQuery} $node jQuery node with .lj-like class
     */
    function parseTwitter($node) {
        var params = null,
            iframe = null,
            // link to replace with iframe
            link = null,
            item = $node.find( selectors.twitter );

        if (item.length === 0) {
            return;
        }

        link = item.children().eq(0);

        params = {
            url: link.data('url'),
            text: link.data('text') || '',
            count: link.data('count'),
            lang: link.data('lang') || 'en',
            hashtags: link.data('hashtags') || ''
        };

        iframe = createIframe({
            src: LiveJournal.constructUrl('http://platform.twitter.com/widgets/tweet_button.html', params)
        });

        link.replaceWith(iframe);
    }

    /**
     * Parse surfingbird share button
     * @param  {jQuery} $node jQuery .lj-like node
     */
    function parseSurfingbird($node) {
        var item = $node.find( selectors.surfingbird ),
            link = null,
            iframe = null,
            params = null;

        if (item.length === 0) {
            return;
        }

        link = item.find('.surfinbird__like_button');
        params = {
            url: link.data('url'),
            caption: link.data('text'),
            layout: 'common'
        };

        iframe = createIframe({
            src: LiveJournal.constructUrl('http://surfingbird.ru/button', params)
        });

        link.replaceWith(iframe);
    }

    /**
     * Parse repost button
     * @param  {jQuery} $node jQuery .lj-like node
     */
    function parseRepost($node) {
        var item = $node.find( selectors.repost ),
            link = null,
            url;

        if (item.length === 0) {
            return;
        }

        link = $node.find('.lj-like-item-repost').find('a'),
        url = link.data('url');

        LJ.Api.call('repost.get_status', { url: url }, function (data) {
            link.replaceWith(LiveJournal.renderRepostButton(url, data));
        });
    }

    return parse;
}());

LiveJournal.renderRepostButton = function (url, data) {
    data = data || {};

    var meta = {
            paid: !!data.paid,
            url: url,
            cost: data.cost,
            budget: data.budget,
            count: Number(data.count || 0),
            reposted: !!data.reposted
        },
        template = 'templates-CleanHtml-Repost',
        options = {},
        node;

    if (meta.paid) {
        template = 'templates-CleanHtml-PaidRepost';
        meta.owner = meta.cost === '0';
        options.classNames = {
            active: 'paidrepost-button-active',
            inactive: 'paidrepost-button-inactive'
        };
    }

    return LJ.UI.template(template, meta).repostbutton(jQuery.extend(options, meta));
};

/**
 * Insert script in the document asynchronously.
 *
 * @param {String}  url     Url of the script
 * @param {Object=} params  Data to apply to the scipt node object, e.g. async, text.
 * @param {Node=}   parent  If exists, script tag will be inserted in this node or before the
 *                          first script tag otherwise.
 *
 * @return {jQuery.Deferred}    jQuery deferred object that will be resolved when
 *                              script loaded.
 */
LiveJournal.injectScript = function(url, params, parent) {
    var deferred = jQuery.Deferred(),
        defaults = {
            async: true
        },
        script,
        prop;

    script = document.createElement('script');
    script.src = url;

    if (params && jQuery.type(params) === 'object') {
        params = jQuery.extend({}, defaults, params);

        for (prop in params) {
            if ( params.hasOwnProperty(prop) ) {
                script[prop] = params[prop];
            }
        }
    }

    if (script.readyState) {
        // IE
        script.onreadystatechange = function () {
            if ( script.readyState === 'loaded' || script.readyState === 'complete' ) {
                script.onreadystatechange = null;
                deferred.resolve();
            }
        };
    } else {
        // Others
        script.onload = function(){
            deferred.resolve();
        };
    }


    if (parent) {
        parent.appendChild(script);
    } else {
        parent = document.getElementsByTagName('script')[0];
        parent.parentNode.insertBefore(script, parent);
    }

    return deferred;
};

LiveJournal.getLocalizedStr = LJ.ml;

LiveJournal.JSON = JSON;

/**
 * Parse link or embed html.
 * @param {String} input Input can contain link or html.
 * @return {Object} Object representing the media.
 */

LiveJournal.parseMedia = (function() {
    'use strict';

    function parseMediaLink(input) {
        var link = {
            'youtube': 'http://youtube.com/watch?v={id}',
            'vimeo': 'http://vimeo.com/{id}',
            'vine': 'http://vine.co/v/{id}',
            'instagram': 'http://instagram.com/p/{id}/',
            'gist' : 'https://gist.github.com/{id}'
        };

        var embed = {
            'youtube': '<iframe src="http://www.youtube.com/embed/{id}" width="560" height="315" frameborder="0" allowfullscreen data-link="{link}"></iframe>'.supplant({link: link.youtube}),
            'vimeo'  : '<iframe src="http://player.vimeo.com/video/{id}" width="560" height="315" frameborder="0" allowfullscreen data-link="{link}"></iframe>'.supplant({link: link.vimeo}),
            'vine'   : '<iframe src="http://vine.co/v/{id}/card" width="380" height="380" frameborder="0" data-link="{link}"></iframe>'.supplant({link: link.vine}),
            'instagram' : '<iframe src="//instagram.com/p/{id}/embed/" width="612" height="710" frameborder="0" scrolling="no" allowtransparency="true"  data-link="{link}"></iframe>'.supplant({link: link.instagram}),
            'gist' : '<a data-expand="false" href="https://gist.github.com/{id}">gist.github.com/{id}</a>'.supplant({link: link.gist})
        };

        var provider = {
            'vine': {
                parse: function(input) {
                    // http://vine.co/v/bdbF0i72uwA
                    var matcher = /vine.co\/v\/([^\/]*)/,
                        match = input.match(matcher);

                    return (match && match[1]) || null;
                }
            },

            'vimeo': {
                parse: function(input) {
                    var matcher = /^(http:\/\/)?(www\.)?(player\.)?vimeo.com\/(video\/)?(\d+)*/,
                        match = input.match(matcher);

                    return (match && match[5]) || null;
                }
            },

            'youtube': {
                parse: function(input) {
                    // http://stackoverflow.com/a/8260383
                    var matcher = /^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\??v?=?))([^#\&\?]*).*/,
                        match = input.match(matcher);

                    if (match && match[0].indexOf('youtu') === -1) {
                        return null;
                    }

                    // we really should move from regexp to querystring parsing
                    var qs = LiveJournal.parseGetArgs(input);
                    if (qs.v) {
                        return qs.v;
                    }

                    return (match && match[7]) || null;
                }
            },

            'instagram': {
                parse: function(input) {
                    var matcher = /.*(?:instagram\.\w*|instagr\.am)\/p\/([^\/]+).*/,
                        match = input.match(matcher);

                    return (match && match[1]) || null;
                }
            },

            'gist': {
                parse: function(input) {
                    var matcher = /.*(?:gist\.github\.com\/)([^\/]+\/{1}[^\/]+)\/{0,1}$/,
                        match = input.match(matcher);

                    return (match && match[1]) || null;
                }
            }
        };

        var id, key, result;
        for (key in provider) {
            id = provider[key].parse(input.trim());
            if (id) {
                result = {
                    site: key,
                    id: id
                };

                if (embed[key]) {
                    result.embed = embed[key].supplant(result);
                }

                if (link[key]) {
                    result.link = link[key].supplant(result);
                }

                return result;
            }
        }

        return null;
    }

    return function(input) {

        // jQuery can fail on input
        try {
            var node = jQuery(input).first(), src;

            if (node && node.prop('tagName').toLowerCase() === 'iframe') {
                src = node && node.attr('src');

                if (src) {
                    return parseMediaLink(src);
                }
            }
        } catch (e) {
            return parseMediaLink(input);
        }
    };
})();
