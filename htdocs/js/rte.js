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

LJTagsInHTML = function(oEditor) {
	var lj_tags = oEditor.EditorDocument.body.getElementsByTagName('lj-template'),
		i = lj_tags.length,
		style_no_edit = 'cursor: default; -moz-user-select: all; -moz-user-input: none; -moz-user-focus: none; -khtml-user-select: all;';
	while (i--) {
		var lj_tag = lj_tags[i],
			name = lj_tag.getAttribute('name');
		switch (name) {
			case 'video':
			case 'qotd':
				break;
			// lj-template any name: <lj-template name="" value="" alt="html code"/>
			default:
				var value = lj_tag.getAttribute('value'),
					alt = lj_tag.getAttribute('alt');
				if (!value || !alt) {
					break;
				}
				var div = oEditor.EditorDocument.createElement('div');
				div.className = 'lj-template';
				div.setAttribute('name', name);
				div.setAttribute('value', value);
				div.setAttribute('alt', alt);
				div.setAttribute('style', style_no_edit);
				div.contentEditable = false;
				div.innerHTML = alt;
				lj_tag.parentNode.replaceChild(div, lj_tag);
		}
	}
}

var switched_rte_on = false;

function useRichText(textArea, statPrefix) {
	var oEditor = window.FCKeditorAPI && FCKeditorAPI.GetInstance(textArea);
	
	if (switched_rte_on == true) {
		oEditor && oEditor.Focus(true);
		return false;
	}

    if ($("insobj")) {
        $("insobj").className = 'on';
    }
    if ($("jrich")) {
        $("jrich").className = 'on';
    }
    if ($("jplain")) {
        $("jplain").className = '';
    }
	$('htmltools').style.display = 'none';

    // Check for RTE already existing. IE will show multiple iframes otherwise.
    if (!oEditor) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + '/fck/';
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = 'Update';
        oFCKeditor.ReplaceTextarea();
    } else {
		var textarea_node = $(textArea);
		textarea_node.style.display = 'none';
		$(textArea + '___Frame').style.display = 'block';
		
		// IE async call SetData
		oEditor.Events.AttachEvent('OnAfterSetHTML', function() {
			oEditor.Focus(true);
			oEditor.LJPollSetKeyPressHandler();
			oEditor.Events.DetachEvent('OnAfterSetHTML', arguments.callee)
		});
		oEditor.SetData(textarea_node.value);
    }

    if ($('qotd_html_preview')) {
       $('qotd_html_preview').style.display = 'none';
    }
	
	switched_rte_on = true;
	$('switched_rte_on').value = '1';
	return false; // do not follow link
}

function getPostText(textArea) {
	var textarea_node = $(textArea);

	if(switched_rte_on == true) {
		var oEditor = FCKeditorAPI.GetInstance(textArea);
		var html = oEditor.GetXHTML(false);
		html = convert_poll_to_ljtags(html);
		html = convert_user_to_ljtags(html);

		return html;
	}
	else {
		return textarea_node.value;
	}
}

function usePlainText(textArea) {
	var textarea_node = $(textArea);
	
	if (switched_rte_on == true)
	{
		switched_rte_on = false;
		$('switched_rte_on').value = '0';
		
		if (FCKeditor_LOADED) {
			var oEditor = FCKeditorAPI.GetInstance(textArea);
		
			if (oEditor.Status == FCK_STATUS_COMPLETE) {
				var html = oEditor.GetXHTML(false);
				html = convert_poll_to_ljtags(html);
				html = convert_user_to_ljtags(html);
				textarea_node.value = html;
			}
		}
	
		if ($('qotd_html_preview')) {
			$("qotd_html_preview").style.display = 'block';
		}
	
		if ($('insobj'))
			$('insobj').className = '';
		if ($('jrich'))
			$('jrich').className = '';
		if ($('jplain'))
			$('jplain').className = 'on';
	
		$(textArea + '___Frame').style.display = 'none';
		textarea_node.style.display = 'block';
		$('htmltools').style.display = 'block';
	}
	// focus to end
	var length = textarea_node.value.length;
	DOM.setSelectedRange(textarea_node, length, length);
	textarea_node.scrollTop = textarea_node.scrollHeight;
	
	return false;
}

function convert_to_draft(html) {
    if (switched_rte_on == false) return html;

    html = convert_poll_to_ljtags(html, true);
    html = convert_user_to_ljtags(html);

    return html;
}

function convert_poll_to_ljtags(html, post)
{
	html = html.replace(/<form (?=[^>]*class="ljpoll")[^>]*data="([^\"]+?)"[^\b]*?<\/form>/gm,
		function(form, data){ return unescape(data); });
	return html;
}

function convert_poll_to_HTML(html)
{
	html = html.replace(/<lj-poll .*?>[^\b]*?<\/lj-poll>/gm, function(ljtags)
	{
		var poll = new Poll(ljtags);
		return poll.outputHTML();
	});
	return html;
}

function convert_qotd_to_HTML(html) {
    var qotdText = LiveJournal.qotdText;

    var styleattr = " style='cursor: default; -moz-user-select: all; -moz-user-input: none; -moz-user-focus: none; -khtml-user-select: all;'";

    html = html
		.replace(/<lj-template(.*?)><\/lj-template>/g, "<lj-template$1 />") // make self-closing tag
		.replace(/<lj-template(.*?)(name=['"]?qotd['"]?)(.*)?\/>/g, '<lj-template class="ljqotd"$1$3/>') // name attrib
		.replace(/<lj-template( class="ljqotd".*?)id=['"]?(\d+)['"]?(.*)?\/>/g, "<lj-template$1qotdid=\"$2\"$3/>") // id attrib
		.replace(/<lj-template( class="ljqotd".*?)\/>/g, '<div$1contentEditable="false"' + styleattr + '>' + qotdText + '</div>\n'); // the main regex
	
    return html;
}

// Constant used to check if FCKeditorAPI is loaded
var FCKeditor_LOADED = false;

function FCKeditor_OnComplete(oEditor) {
	oEditor.Events.AttachEvent('OnAfterLinkedFieldUpdate', doLinkedFieldUpdate);
	oEditor.Events.AttachEvent('OnAfterSetHTML', function() {
		LJUser(oEditor);
		LJTagsInHTML(oEditor);
	});
	oEditor.LJPollSetKeyPressHandler();
	LJUser(oEditor);
	LJTagsInHTML(oEditor);
	$('updateForm').onsubmit = function() {
		if (switched_rte_on == false) return;
		
		var html = oEditor.GetXHTML(false);
		html = convert_poll_to_ljtags(html, true);
		html = convert_user_to_ljtags(html);
		this['draft'].value = html;
	}
	FCKeditor_LOADED = true;
	oEditor.Focus(true);
}

function doLinkedFieldUpdate(oEditor) {
	var html = oEditor.GetXHTML(false);
	html = convert_poll_to_ljtags(html);
	html = convert_user_to_ljtags(html)
	$('draft').value = html;
}

function convert_user_to_ljtags(html) {
	html = html
		.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/.*?<b>\1<\/b><\/a><\/span>/g, '<lj comm="$1"/>')
		.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/.*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj comm="$1" title="$2"/>')
		.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/users\.[-.\w]+\/([\w]+)\/.*?<b>\1<\/b><\/a><\/span>/g, '<lj user="$1"/>') // username with special symbol
		.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/users\.[-.\w]+\/([\w]+)\/.*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$2"/>')

		//handle ext_ nicknames
		.replace(/<span[^>]*?lj:user="(ext_\d+)"[^>]*?><a>?(.*?)<\/a><a[^<]*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$3"/>')

		.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/([-\w]+)\..*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$2"/>')
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
	html = html
		.replace(/<lj-template name=['"]video['"]>(\S+?)<\/lj-template>/g, '<div class="ljvideo" url="$1"><img src="' + Site.statprefix + '/fck/editor/plugins/livejournal/ljvideo.gif" /></div>')
		// Match across multiple lines and extract ID if it exists
		.replace(/<lj-embed\s*(id="(\d*)")?\s*>\s*(.*)\s*<\/lj-embed>/gim, '<div class="ljembed" embedid="$2">$3</div>')
	
    html = convert_poll_to_HTML(html);
    html = convert_qotd_to_HTML(html);

    return html;
}
// Utit test
//document.write('<script src="/js/test/rte.js"></script>');
