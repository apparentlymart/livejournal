function LJUser(oEditor) {
    var html = oEditor.GetXHTML(false);

    var regexp = /<lj (?:title="([^">]+)?")? ?(?:comm|user)="(\w+?)" ?(?:title="([^">]+)?")? ?\/?>/g,
        orig_html = html,
        ljusers;

    while (ljusers = regexp.exec(html)) {
        var username = ljusers[2],
            usertitle = ljusers[1] || ljusers[3],
            cachename = usertitle ? username + ':' + usertitle : username;

        if (LJUser.cache[cachename]) {
            if (LJUser.cache[cachename].html) {
                html = html.replace(ljusers[0], LJUser.cache[cachename].html);
            }
            continue;
        }

        LJUser.cache[cachename] = {}

        var postData = {
            username: username
        }

        if (usertitle)
            postData.usertitle = usertitle;

        var gotError = (function(username) { return function(err) {
            alert(err + ' "' + username + '"');
        }})(username);

        var gotInfo = (function(userstr, username, cachename) { return function (data) {
            if (data.error) {
                return alert(data.error+' "'+username+'"');
            }
            if (!data.success) return;
            data.ljuser = data.ljuser
                .replace(/<span.+?class='ljuser'?.+?>/, '<div class="ljuser">')
                .replace(/<\/span>\s?/, '</div>');
            html = html.replace(userstr, data.ljuser);
            LJUser.cache[cachename].html = data.ljuser;
            oEditor.SetData(html);
        }})(ljusers[0], username, cachename);

        var opts = {
            data:  HTTPReq.formEncoded(postData),
            method: 'POST',
            url: Site.siteroot + '/tools/endpoints/ljuser.bml',
            onError: gotError,
            onData: gotInfo
        }

        HTTPReq.getJSON(opts);
    }
    if (html != orig_html) {
        oEditor.SetData(html);
    }
}
LJUser.cache = {}

function useRichText(textArea, statPrefix) {
    if ($("switched_rte_on").value == '1') return;

    if ($("insobj")) {
        $("insobj").className = 'on';
    }
    if ($("jrich")) {
        $("jrich").className = 'on';
    }
    if ($("jplain")) {
        $("jplain").className = '';
    }
    if ($("htmltools")) {
        $("htmltools").style.display = 'none';
    }

    var entry_html = $(textArea).value;

    entry_html = convertToHTMLTags(entry_html, statPrefix);
    if (!$('event_format').checked) {
        entry_html = entry_html.replace(/\n/g, '<br />');
    }

    var editor_frame = $(textArea + '___Frame');
    // Check for RTE already existing.  IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + '/fck/';
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = 'Update';
        $(textArea).value = entry_html;
        oFCKeditor.ReplaceTextarea();
    } else {
        editor_frame.style.display = 'block';
        $(textArea).style.display = 'none';
        if (window.FCKeditorAPI) {
            var oEditor = FCKeditorAPI.GetInstance(textArea);
            oEditor.SetData(entry_html);
            oEditor.Focus();
            oEditor.switched_rte_on = '1'; // Hack for handling submitHandler
        }
    }

    if ($('qotd_html_preview')) {
       $('qotd_html_preview').style.display = 'none';
    }

    $('switched_rte_on').value = '1';

    return false; // do not follow link
}

function usePlainText(textArea) {
    if ($('switched_rte_on').value == '0') return;

    if (FCKeditor_LOADED) {
        var oEditor = FCKeditorAPI.GetInstance(textArea);

        if (oEditor.Status == FCK_STATUS_COMPLETE) {
            var html = oEditor.GetXHTML(false);
            html = convertToLJTags(html);
            if (!$('event_format').checked) {
                html = html
                    .replace(/<br \/>/g, '\n')
                    .replace(/<p>(.*?)<\/p>/g, '$1\n')
                    .replace(/&nbsp;/g, ' ');
            }
            $(textArea).value = html;
        }
        // Hack for handling submitHandler
        oEditor.switched_rte_on = '0';
    } else {
        if (!$('event_format').checked) {
            $(textArea).value = $(textArea).value.replace(/<br \/>/g, '\n');
        }
    }

    var editor_frame = $(textArea + '___Frame');

    if ($('qotd_html_preview')) {
       $("qotd_html_preview").style.display='block';
    }

    if ($('insobj'))
        $('insobj').className = '';
    if ($('jrich'))
        $('jrich').className = '';
    if ($('jplain'))
        $('jplain').className = 'on';
    editor_frame.style.display = 'none';
    $(textArea).style.display = 'block';
    $('htmltools').style.display = 'block';
    $('switched_rte_on').value = '0';

    return false;
}

function convert_post(textArea) {
    if ($("switched_rte_on").value == '0') return;

    var oEditor = FCKeditorAPI.GetInstance(textArea);
    var html = oEditor.GetXHTML(false);

    var tags = convert_poll_to_ljtags(html, true);
    tags = convert_qotd_to_ljtags(tags);

    $(textArea).value = tags;
    oEditor.SetData(tags);
}

function convert_to_draft(html) {
    if ($("switched_rte_on").value == '0') return html;

    var out = convert_poll_to_ljtags(html, true);
    out = convert_qotd_to_ljtags(out);
    out = out.replace(/\n/g, '');

    return out;
}

function convert_poll_to_ljtags (html, post) {
    var tags = html.replace(/<div id=['"]poll(.+?)['"]>[^\b]*?<\/div>/gm,
                            function (div, id){ return generate_ljpoll(id, post) } );
    return tags;
}

function generate_ljpoll(pollID, post) {
    var poll = LJPoll[pollID];
    var tags = poll.outputLJtags(pollID, post);
    return tags;
}

function convert_poll_to_HTML(plaintext) {
    var html = plaintext.replace(/<lj-poll name=['"].*['"] id=['"]poll(\d+?)['"].*>[^\b]*?<\/lj-poll>/gm,
                                 function (ljtags, id){ return generate_pollHTML(ljtags, id) } );
    return html;
}

function generate_pollHTML(ljtags, pollID) {
    try {
        var poll = LJPoll[pollID];
    } catch (e) {
        return ljtags;
    }

    var tags = "<div id=\"poll"+pollID+"\">";
    tags += poll.outputHTML();
    tags += "</div>";

    return tags;
}

function convert_qotd_to_ljtags(html) {
    // div tag and qotdid attrib
    var tags = html.replace(/<div(.*)qotdid=['"]?(\d+)['"]?([^>]*)>[^\b]*<\/div>(<br \/>)*/g, "<lj-template id=\"$2\"$1$3 /><br />");
    // class attrib
    tags = tags.replace(/(<lj-template id=\"\d+\" )(.*)class=['"]?ljqotd['"]?([^>]*\/>)?/g, "$1name=\"qotd\" $2$3");
    // lang attrib
    tags = tags.replace(/(<lj-template id=\"\d+\" name=\"qotd\" )(.*)(lang=['"]?(\w+)['"]?)([^>]*\/>)?/g, "$1$3 \/>");

    return tags;
}

function convert_qotd_to_HTML(html) {
    var qotdText = LiveJournal.qotdText;

    var styleattr = " style='cursor: default; -moz-user-select: all; -moz-user-input: none; -moz-user-focus: none; -khtml-user-select: all;'";

    // make self-closing tag
    html = html.replace(/<lj-template(.*)><\/lj-template>/g, "<lj-template$1 />");
    // name attrib
    html = html.replace(/<lj-template(.*)(name=['"]?qotd['"]?)(.*)?\/>/g, "<lj-template$1class=\"ljqotd\"$3/>");
    // id attrib
    html = html.replace(/<lj-template(.*)id=['"]?(\d+)['"]?(.*)?\/>/g, "<lj-template$1qotdid=\"$2\"$3/>");
    // the main regex
    html = html.replace(/<lj-template(.*?)\/>/g, "<div$1contenteditable=\"false\"" + styleattr + ">" + qotdText + "</div>\n");

    return html;
}

// Constant used to check if FCKeditorAPI is loaded
var FCKeditor_LOADED = false;

function FCKeditor_OnComplete(oEditor) {
    oEditor.Events.AttachEvent('OnAfterLinkedFieldUpdate', doLinkedFieldUpdate);
    oEditor.Events.AttachEvent('OnAfterSetHTML', function() { LJUser(oEditor) });
    LJUser(oEditor);
    FCKeditor_LOADED = true;
}

function doLinkedFieldUpdate(oEditor) {
    var html = oEditor.GetXHTML(false);
    var tags = convertToLJTags(html);

    $('draft').value = tags;
}

function convertToLJTags(html) {
    html = html
        .replace(/<div class="ljuser"><a href="http:\/\/community\.[-.\w]+\/([_\w]+)\/(?:[^<]|<[^b])*<b>\1<\/b><\/a><\/div>/g, '<lj comm="$1"/>')
        .replace(/<div class="ljuser"><a href="http:\/\/community\.[-.\w]+\/([_\w]+)\/(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/div>/g, '<lj comm="$1" title="$2"/>')
        .replace(/<div class="ljuser"><a href="http:\/\/users\.[-.\w]+\/([_\w]+)\/(?:[^<]|<[^b])*<b>\1<\/b><\/a><\/div>/g, '<lj user="$1"/>')
        .replace(/<div class="ljuser"><a href="http:\/\/users\.[-.\w]+\/([_\w]+)\/(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/div>/g, '<lj user="$1" title="$2"/>')
        .replace(/<div class="ljuser"><a href="http:\/\/([_\w]+)\.(?:[^<]|<[^b])*<b>\1<\/b><\/a><\/div>/g, '<lj user="$1"/>')
        .replace(/<div class="ljuser"><a href="http:\/\/([_\w]+)\.(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/div>/g, '<lj user="$1" title="$2"/>')
        .replace(/<\/lj>/g, '')
        .replace(/<div class=['"]ljvideo['"] url=['"](\S+)['"]><img.+?\/><\/div>/g, '<lj-template name="video">$1</lj-template>')
        .replace(/<div class=['"]ljvideo['"] url=['"](\S+)['"]><br \/><\/div>/g, '')
        .replace(/<div class=['"]ljraw['"]>(.+?)<\/div>/g, '<lj-raw>$1</lj-raw>')
        .replace(/<div class=['"]ljembed['"](\s*embedid="(\d*)")?\s*>(.*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')
        .replace(/<div\s*(embedid="(\d*)")?\s*class=['"]ljembed['"]\s*>(.*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')
        .replace(/<div class=['"]ljcut['"] text=['"](.+?)['"]>(.+?)<\/div>/g, '<lj-cut text="$1">$2</lj-cut>')
        .replace(/<div text=['"](.+?)['"] class=['"]ljcut['"]>(.+?)<\/div>/g, '<lj-cut text="$1">$2</lj-cut>')
        .replace(/<div class=['"]ljcut['"]>(.+?)<\/div>/g, '<lj-cut>$1</lj-cut>');

    html = convert_poll_to_ljtags(html);
    html = convert_qotd_to_ljtags(html);
    return html;
}

function convertToHTMLTags(html, statPrefix) {
    html = html.replace(/<lj-cut text=['"](.+?)['"]>([\S\s]+?)<\/lj-cut>/gm, '<div text="$1" class="ljcut">$2</div>');
    html = html.replace(/<lj-cut>([\S\s]+?)<\/lj-cut>/gm, '<div class="ljcut">$1</div>');
    html = html.replace(/<lj-raw>([\w\s]+?)<\/lj-raw>/gm, '<div class="ljraw">$1</div>');
    html = html.replace(/<lj-template name=['"]video['"]>(\S+?)<\/lj-template>/g, "<div url=\"$1\" class=\"ljvideo\"><img src='" + statPrefix + "/fck/editor/plugins/livejournal/ljvideo.gif' /></div>");
    // Match across multiple lines and extract ID if it exists
    html = html.replace(/<lj-embed\s*(id="(\d*)")?\s*>\s*(.*)\s*<\/lj-embed>/gim, '<div class="ljembed" embedid="$2">$3</div>');

    html = convert_poll_to_HTML(html);
    html = convert_qotd_to_HTML(html);

    return html;
}
// Utit test
//document.write('<script src="/js/test/rte.js"></script>');
