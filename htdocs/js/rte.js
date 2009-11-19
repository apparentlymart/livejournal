function LJUser(oEditor) {
	var lj_tags = oEditor.EditorDocument.body.getElementsByTagName('lj'),
		i = lj_tags.length;
	
	while (i--) {
		var lj_tag = lj_tags[i],
			username = lj_tag.getAttribute('user') || lj_tag.getAttribute('comm'),
			usertitle = lj_tag.getAttribute('title'),
			cachename = usertitle ? username + ':' + usertitle : username;
		if (LJUser.cache[cachename]) {
			if (LJUser.cache[cachename].html) {
				var node = oEditor.EditorDocument.createElement('b');
				node.innerHTML = LJUser.cache[cachename].html;
				lj_tag.parentNode.replaceChild(node.firstChild, lj_tag);
			} else {
				LJUser.cache[cachename].queue.push(lj_tag);
			}
			continue;
		}
		
		LJUser.cache[cachename] = {
			queue: [lj_tag]
		}

        var postData = {
            username: username
        }

        if (usertitle)
            postData.usertitle = usertitle;

        var gotError = (function(username) { return function(err) {
            alert(err + ' "' + username + '"');
        }})(username);

        var gotInfo = (function(username, cachename) { return function (data) {
            if (data.error) {
                return alert(data.error+' "'+username+'"');
            }
            if (!data.success) return;
			
			data.ljuser = data.ljuser.replace("<span class='useralias-value'>*</span>", '');
			
			var lj_tag;
			while(lj_tag = LJUser.cache[cachename].queue.shift()) {
				var node = oEditor.EditorDocument.createElement('b');
				node.innerHTML = data.ljuser;
				lj_tag.parentNode.replaceChild(node.firstChild, lj_tag);
			}
			
			LJUser.cache[cachename].html = data.ljuser;
        }})(username, cachename);

        var opts = {
            data:  HTTPReq.formEncoded(postData),
            method: 'POST',
            url: Site.siteroot + '/tools/endpoints/ljuser.bml',
            onError: gotError,
            onData: gotInfo
        }

        HTTPReq.getJSON(opts);
    }
}
LJUser.cache = {}

var switched_rte_on = false;

function useRichText(textArea, statPrefix) {
    if (switched_rte_on == true) return;

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

    var editor_frame = $(textArea + '___Frame');
    // Check for RTE already existing. IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + '/fck/';
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = 'Update';
        oFCKeditor.ReplaceTextarea();
    } else {
        editor_frame.style.display = 'block';
        $(textArea).style.display = 'none';
        if (window.FCKeditorAPI) {
            var oEditor = FCKeditorAPI.GetInstance(textArea);
            oEditor.SetData($(textArea).value);
            oEditor.Focus();
        }
    }

    if ($('qotd_html_preview')) {
       $('qotd_html_preview').style.display = 'none';
    }

    switched_rte_on = true;

    return false; // do not follow link
}

function usePlainText(textArea) {
    if (switched_rte_on == false) return;

    if (FCKeditor_LOADED) {
        var oEditor = FCKeditorAPI.GetInstance(textArea);

        if (oEditor.Status == FCK_STATUS_COMPLETE) {
            var html = oEditor.GetXHTML(false);

			html = convert_poll_to_ljtags(html);
			html = convert_user_to_ljtags(html);
            $(textArea).value = html;
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
    switched_rte_on = false;

    return false;
}

function convert_to_draft(html) {
    if (switched_rte_on == false) return html;

    html = convert_poll_to_ljtags(html, true);
    html = convert_user_to_ljtags(html);

    return html;
}

function convert_poll_to_ljtags (html, post) {
    html = html.replace(/<div id=['"]poll(.+?)['"]>[^\b]*?<\/div>/gm,
                            function (div, id){ return generate_ljpoll(id, post) } );
    return html;
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

    var tags = '<div id="poll'+pollID+'">';
    tags += poll.outputHTML();
    tags += '</div>';

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
	$('updateForm').onsubmit = function() {
		if (switched_rte_on == false) return;
		
		var html = oEditor.GetXHTML(false);
		
		html = convert_poll_to_ljtags(html, true);
		html = convert_user_to_ljtags(html);
		this['draft'].value = html;
	}
	FCKeditor_LOADED = true;
}

function doLinkedFieldUpdate(oEditor) {
	var html = oEditor.GetXHTML(false);
	html = convert_poll_to_ljtags(html);
	html = convert_user_to_ljtags(html)
	$('draft').value = html;
}

function convert_user_to_ljtags(html) {
	html = html
		.replace(/<span.*?class="ljuser.*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/(?:[^<]|<[^b])*<b>\1<\/b><\/a><\/span>/g, '<lj comm="$1"/>')
		.replace(/<span.*?class="ljuser.*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj comm="$1" title="$2"/>')
		.replace(/<span.*?class="ljuser.*?><a href="http:\/\/users\.[-.\w]+\/([\w]+)\/(?:[^<]|<[^b])*<b>\1<\/b><\/a><\/span>/g, '<lj user="$1"/>') // username with special symbol
		.replace(/<span.*?class="ljuser.*?><a href="http:\/\/users\.[-.\w]+\/([\w]+)\/(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$2"/>')
		.replace(/<span.*?class="ljuser.*?><a href="http:\/\/([-\w]+)\.(?:[^<]|<[^b])*<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$2"/>')
		.replace(/<\/lj>/g, '');
	
	//change user-name to user_name
	var ljuser,
		rex = /<lj user="([-\w]+)"([^>]+)?\/>/g;
	while(ljuser = rex.exec(html)) {
		html = html.replace(ljuser[0], '<lj user="'+ljuser[1].replace(/-/g, '_')+'"'+(ljuser[2]||'')+'/>');
	}
	
	// for ex.: <lj user="tester_1" title="tester_1"/>
	html = html.replace(/<lj user="([\w]+)" title="\1"\/>/g, '<lj user="$1"/>');
	
	return html;
}

function convertToLJTags(html) {
    html = html
        .replace(/<div(?=[^>]*class="ljvideo")[^>]*url="(\S+)"[^>]*><img.+?\/><\/div>/g, '<lj-template name="video">$1</lj-template>')
        .replace(/<div(?=[^>]*class="ljvideo")[^>]*url="\S+"[^>]*>(.+?)<\/div>/g, '<p>$1</p>') // video img replaced on text
        .replace(/<div class=['"]ljembed['"](\s*embedid="(\d*)")?\s*>(.*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')
        .replace(/<div\s*(embedid="(\d*)")?\s*class=['"]ljembed['"]\s*>(.*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')
        // convert qotd
		.replace(/<div([^>]*)qotdid="(\d+)"([^>]*)>[^\b]*<\/div>(<br \/>)*/g, '<lj-template id="$2"$1$3 /><br />') // div tag and qotdid attrib
		.replace(/(<lj-template id="\d+" )([^>]*)class="ljqotd"?([^>]*\/>)/g, '$1name="qotd" $2$3') // class attrib
		.replace(/(<lj-template id="\d+" name="qotd" )[^>]*(lang="\w+")[^>]*\/>/g, '$1$2 \/>'); // lang attrib
	
	return html;
}

function convertToHTMLTags(html) {
    html = html.replace(/<lj-template name=['"]video['"]>(\S+?)<\/lj-template>/g, '<div class="ljvideo" url="$1"><img src="' + Site.statprefix + '/fck/editor/plugins/livejournal/ljvideo.gif" /></div>');
    // Match across multiple lines and extract ID if it exists
    html = html.replace(/<lj-embed\s*(id="(\d*)")?\s*>\s*(.*)\s*<\/lj-embed>/gim, '<div class="ljembed" embedid="$2">$3</div>');

    html = convert_poll_to_HTML(html);
    html = convert_qotd_to_HTML(html);

    return html;
}
// Utit test
//document.write('<script src="/js/test/rte.js"></script>');
