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
        LJ.Api.init({ auth_token: LJ.get('auth_token') });
    }

    LJ.UI.bootstrap();

    //register system hooks
    LiveJournal.register_hook('update_wallet_balance', LiveJournal.updateWalletBalance);
    LiveJournal.register_hook('xdr/message', LiveJournal.processXdr);

    LiveJournal.initSpoilers();
    LiveJournal.initResizeHelper();

    //ljuniq cookie is checked here now instead of PageStats/Omniture.pm
    LiveJournal.checkLjUniq();

    // run other hooks
    LiveJournal.run_hook('page_load');

    // Lazy like buttons loader
    jQuery(document.body).ljLikes();
};

/**
 * Special helper class is added to the body if browser doesn't support media queries and
 * screen width is less then 1000px.
 */
LiveJournal.initResizeHelper = function() {
    var $window = jQuery(window),
        $body = jQuery('body'),
        hasClass = false,
        resizeFunc = LJ.Function.throttle(function() {
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

    return LJ.get('currentJournal') ? '/' + LJ.get('currentJournal') + '/__rpc_' + action : '/__rpc_' + action;
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
                domain: LJ.get('siteroot').replace(/^https?:\/\/www\./, ''),
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

LiveJournal.getLocalizedStr = LJ.ml;

LiveJournal.JSON = JSON;
