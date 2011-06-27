(function(){
	var cache= {};

	function updateLJUser(ljTag, html){
		var node = CKEditor.document.$.createElement('b');
		node.innerHTML = html;
		ljTag.parentNode.replaceChild(node.firstChild, ljTag);
	}

	function LJToHtml(){
		var insobj = $('insobj');
		if(insobj){
			insobj.className = 'on';
		}

		var jrich = $('jrich');
		if(jrich){
			jrich.className = 'on';
		}

		var jplain = $('jplain');
		if(jplain){
			jplain.className = '';
		}

		var htmltools = $('htmltools');
		if(htmltools){
			htmltools.style.display = 'none';
		}

		var preview = $('qotd_html_preview');
		if(preview){
			preview.style.display = 'none';
		}

		CKEditor.container.show();
		CKEditor.element.hide();

		var ljTags = CKEditor.document.getElementsByTag('lj').$,
			i = ljTags.length;

		while(i--){
			var ljTag = ljTags[i],
				userName = ljTag.getAttribute('user') || ljTag.getAttribute('comm'),
				T = ljTag.getAttribute('title'),
				cacheName = T ? userName + ':' + T : userName;
			if(cache.hasOwnProperty(cacheName)){
				if(cache[cacheName].html){
					updateLJUser(ljTag, cache[cacheName].html);
				} else {
					cache[cacheName].queue.push(ljTag);
				}
				continue;
			}

			cache[cacheName] = {
				queue: [ljTag]
			};

			var postData = {
				username: userName
			};

			if(T){
				postData.usertitle = T;
			}

			var gotError = (function(username){
				return function(err){
					alert(err + ' "' + username + '"');
				}
			})(userName);

			var gotInfo = (function(username, cachename){
				return function (data){
					if(data.error){
						return alert(data.error + ' "' + username + '"');
					}
					if(!data.success){
						return;
					}

					data.ljuser = data.ljuser.replace("<span class='useralias-value'>*</span>", '');

					var ljTag;
					while(ljTag = cache[cachename].queue.shift()){
						updateLJUser(ljTag, data.ljuser);
					}

					cache[cachename].html = data.ljuser;
				}
			})(userName, cacheName);

			HTTPReq.getJSON({
				data: HTTPReq.formEncoded(postData),
				method: 'POST',
				url: Site.siteroot + '/tools/endpoints/ljuser.bml',
				onError: gotError,
				onData: gotInfo
			});
		}

		ljTags = CKEditor.document.getElementsByTag('lj-template').$,i = ljTags.length;
		var styleNoEdit = 'cursor: default; -moz-user-select: all; -moz-user-input: none; -moz-user-focus: none; -khtml-user-select: all;';
		while(i--){
			ljTag = ljTags[i];
			var name = ljTag.getAttribute('name');
			switch(name){
				case 'video':
				case 'qotd':
					break;
				default:
					var value = ljTag.getAttribute('value'),
						alt = ljTag.getAttribute('alt');
					if(!value || !alt){
						break;
					}
					var div = CKEditor.document.$.createElement('div');
					div.className = 'lj-template';
					div.setAttribute('name', name);
					div.setAttribute('value', value);
					div.setAttribute('alt', alt);
					div.setAttribute('style', styleNoEdit);
					div.contentEditable = false;
					div.innerHTML = alt;
					ljTag.parentNode.replaceChild(div, ljTag);
			}
		}

		return false;
	}

	window.switchedRteOn = false;
	var CKEditor;

	var closeEmptyTags = function(data){
		return data.replace(/<((?!br)[^\s>]+)([^\/>]+)?\/>/gi, '<$1$2></$1>');
	};

	window.useRichText = function (textArea, statPrefix){
		if(!switchedRteOn){
			switchedRteOn = true;
			$('switched_rte_on').value = '1';

			if(!CKEditor && CKEDITOR && CKEDITOR.env.isCompatible){
				var editor = CKEDITOR.replace(textArea, {
					skin: 'v2',
					baseHref: statPrefix + '/ck/',
					height: 350
				});

				editor.on('instanceReady', function(){
					CKEditor = editor;

					/*$('updateForm').onsubmit = function(){
						if(switchedRteOn){
							var html = closeEmptyTags(CKEditor.element.getValue());
							CKEditor.setData(html);
						}
					};*/
					
					CKEditor.on('dataReady', LJToHtml);
				});
			} else {
				var data = CKEditor.element.getValue();

				var commands = CKEditor._.commands;
				for(var command in CKEditor._.commands){
					if(commands.hasOwnProperty(command) && commands[command].state == CKEDITOR.TRISTATE_ON){
						commands[command].setState(CKEDITOR.TRISTATE_OFF);
					}
				}
				
				data = closeEmptyTags(data);
				CKEditor.setData(data);
			}
		}
		return false; // do not follow link
	};

	window.usePlainText = function(textArea){
		if(switchedRteOn){
			switchedRteOn = false;
			$('switched_rte_on').value = '0';

			if(CKEditor){
				var data = CKEditor.getData();
				data = convertUserAndPool(data);
				CKEditor.element.setValue(data);
				
				CKEditor.container.hide();
				CKEditor.element.show();
			}

			var insobj = $('insobj');
			if(insobj){
				insobj.className = '';
			}

			var jrich = $('jrich');
			if(jrich){
				jrich.className = '';
			}

			var jplain = $('jplain');
			if(jplain){
				jplain.className = 'on';
			}

			var htmltools = $('htmltools');
			if(htmltools){
				htmltools.style.display = 'block';
			}

			var preview = $('qotd_html_preview');
			if(preview){
				preview.style.display = 'block';
			}

			var textareaNode = $(textArea);
			if(textareaNode){
				textareaNode.style.cssText = 'display:block';
			}
		}

		return false;
	};

	function convertUserAndPool(html){
		html = html.replace(/<form.*?class="ljpoll" data="([^"]*)"[\s\S]*?<\/form>/gi, function(form, data){
			return unescape(data);
		})
			.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/.*?<b>\1<\/b><\/a><\/span>/g, '<lj comm="$1"/>')
			.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/(?:community|syndicated)\.[-.\w]+\/([\w]+)\/.*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj comm="$1" title="$2"/>')
			.replace(/<span[^>]*?class="ljuser[^>]*?><a href="http:\/\/users\.[-.\w]+\/([\w]+)\/.*?<b>\1<\/b><\/a><\/span>/g, '<lj user="$1"/>')
			.replace(/<span[^>]*?class="ljuser[^>]*?lj:user="([^"]*?)".+(?!<\/a>).*?<b>([^<]+)?<\/b><\/a><\/span>/g, '<lj user="$1" title="$2"/>')
			.replace(/<\/lj>/g, '');

		//change user-name to user_name
		var ljUser, rex = /<lj user="([-\w]+)"([^>]+)?\/>/g;
		while(ljUser = rex.exec(html)){
			html = html.replace(ljUser[0], '<lj user="' + ljUser[1].replace(/-/g, '_') + '"' + (ljUser[2] || '') + '/>');
		}

		return html.replace(/<lj user="([\w]+)" title="\1"\/>/g, '<lj user="$1"/>');
	}

	window.convertToLJTags = function(html){
		return convertUserAndPool(html)
			.replace(/<div(?=[^>]*class="ljvideo")[^>]*url="(\S+)"[^>]*><img.+?\/><\/div>/g, '<lj-template name="video">$1</lj-template>')
			.replace(/<div(?=[^>]*class="ljvideo")[^>]*url="\S+"[^>]*>([\s\S]+?)<\/div>/g, '<p>$1</p>')
			.replace(/<div class=['"]ljembed['"](\s*embedid="(\d*)")?\s*>([\s\S]*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')
			.replace(/<div\s*(embedid="(\d*)")?\s*class=['"]ljembed['"]\s*>([\s\S]*?)<\/div>/gi, '<lj-embed id="$2">$3</lj-embed>')// convert qotd
			.replace(/<div([^>]*)qotdid="(\d+)"([^>]*)>[^\b]*<\/div>(<br \/>)*/g, '<lj-template id="$2"$1$3 /><br />')// div tag and qotdid attrib
			.replace(/(<lj-template id="\d+" )([^>]*)class="ljqotd"?([^>]*\/>)/g, '$1name="qotd" $2$3')// class attrib
			.replace(/(<lj-template id="\d+" name="qotd" )[^>]*(lang="\w+")[^>]*\/>/g, '$1$2 \/>'); // lang attrib
	};

	window.convertToHTMLTags = function(html){
		return html
			.replace(/<lj-template name=['"]video['"]>(\S+?)<\/lj-template>/g, '<div class="ljvideo" url="$1"><img src="' + Site.statprefix + '/fck/editor/plugins/livejournal/ljvideo.gif" /></div>')
			.replace(/<lj-embed\s*(?:id="(\d*)")?\s*>([\s\S]*?)<\/lj-embed>/gi, '<div class="ljembed" embedid="$1">$2</div>')
			.replace(/<lj-poll .*?>[^b]*?<\/lj-poll>/gm, function(ljtags){
				return new Poll(ljtags).outputHTML();
			})
			.replace(/<lj-template(.*?)><\/lj-template>/g, "<lj-template$1 />");
	};

	window.convertToDraft = function(html){
		return switchedRteOn ? convertUserAndPool(html) : html;
	}
})();