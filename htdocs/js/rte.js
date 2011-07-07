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

		var ljTags = CKEditor.document.getElementsByTag('lj-template').$,i = ljTags.length;
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
			window.switchedRteOn = true;
			$('switched_rte_on').value = '1';

			if(!CKEditor && CKEDITOR && CKEDITOR.env.isCompatible){
				CKEDITOR.basePath = statPrefix + '/ck/';
				var editor = CKEDITOR.replace(textArea, {
					skin: 'v2',
					baseHref: CKEDITOR.basePath,
					height: 350
				});

				editor.on('instanceReady', function(){
					CKEditor = editor;

					$('updateForm').onsubmit = function(){
						if(switchedRteOn){
							this['draft'].value = CKEditor.getData();
						}
					};

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
			window.switchedRteOn = false;
			$('switched_rte_on').value = '0';

			if(CKEditor){
				var data = CKEditor.getData();
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
})();