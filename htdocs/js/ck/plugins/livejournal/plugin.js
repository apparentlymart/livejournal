(function() {
	var dtd = CKEDITOR.dtd;

	dtd.$block['lj-template'] = 1;
	dtd.$block['lj-raw'] = 1;
	dtd.$block['lj-cut'] = 1;
	dtd.$block['lj-poll'] = 1;
	dtd.$block['lj-pq'] = 1;
	dtd.$block['lj-pi'] = 1;
	dtd.$nonEditable['lj-template'] = 1;

	dtd['lj-template'] = {};
	dtd['lj-map'] = {};
	dtd['lj-raw'] = dtd.div;
	dtd['lj-cut'] = dtd.div;

	dtd['lj-poll'] = {
		'lj-pq': 1
	};

	dtd['lj-pq'] = {
		'#': 1,
		'lj-pi': 1
	};

	dtd['lj-pi'] = {
		'#': 1
	};

	dtd.$block.iframe = dtd.$inline.iframe;
	delete dtd.$inline.iframe;

	CKEDITOR.tools.extend(dtd.div, dtd.$block);
	CKEDITOR.tools.extend(dtd.$body, dtd.$block);

	delete dtd['lj-cut']['lj-cut'];

	var likeButtons = [
		{
			label: top.CKLang.LJLike_button_facebook,
			id: 'facebook',
			abbr: 'fb',
			html: '<span class="lj-like-item fb">' + top.CKLang.LJLike_button_facebook + '</span>',
			htmlOpt: '<li class="like-fb"><input type="checkbox" id="like-fb" /><label for="like-fb">' + top.CKLang.LJLike_button_facebook + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_twitter,
			id: 'twitter',
			abbr: 'tw',
			html: '<span class="lj-like-item tw">' + top.CKLang.LJLike_button_twitter + '</span>',
			htmlOpt: '<li class="like-tw"><input type="checkbox" id="like-tw" /><label for="like-tw">' + top.CKLang.LJLike_button_twitter + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_google,
			id: 'google',
			abbr: 'go',
			html: '<span class="lj-like-item go">' + top.CKLang.LJLike_button_google + '</span>',
			htmlOpt: '<li class="like-go"><input type="checkbox" id="like-go" /><label for="like-go">' + top.CKLang.LJLike_button_google + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_vkontakte,
			id: 'vkontakte',
			abbr: 'vk',
			html: '<span class="lj-like-item vk">' + top.CKLang.LJLike_button_vkontakte + '</span>',
			htmlOpt: window.isSupUser ? '<li class="like-vk"><input type="checkbox" id="like-vk" /><label for="like-vk">' + top.CKLang.LJLike_button_vkontakte + '</label></li>' : ''
		},
		{
			label: top.CKLang.LJLike_button_give,
			id: 'livejournal',
			abbr: 'lj',
			html: '<span class="lj-like-item lj">' + top.CKLang.LJLike_button_give + '</span>',
			htmlOpt: '<li class="like-lj"><input type="checkbox" id="like-lj" /><label for="like-lj">' + top.CKLang.LJLike_button_give + '</label></li>'
		}
	];

	var ljTagsData = {
		LJPollLink: {
			html: encodeURIComponent(top.CKLang.Poll_PollWizardNotice + '<br /><a href="#" lj-cmd="LJPollLink">' + top.CKLang.Poll_PollWizardNoticeLink + '</a>')
		},
		LJLike: {
			html: encodeURIComponent(top.CKLang.LJLike_WizardNotice + '<br /><a href="#" lj-cmd="LJLike">' + top.CKLang.LJLike_WizardNoticeLink + '</a>')
		},
		LJUserLink: {
			html: encodeURIComponent(top.CKLang.LJUser_WizardNotice + '<br /><a href="#" lj-cmd="LJUserLink">' + top.CKLang.LJUser_WizardNoticeLink + '</a>')
		},
		LJLink: {
			html: encodeURIComponent(top.CKLang.LJLink_WizardNotice + '<br /><a href="#" lj-cmd="LJLink">' + top.CKLang.LJLink_WizardNoticeLink + '</a>')
		},
		image: {
			html: encodeURIComponent(top.CKLang.LJImage_WizardNotice + '<br /><a href="#" lj-cmd="image">' + top.CKLang.LJImage_WizardNoticeLink + '</a>')
		},
		LJCut: {
			html: encodeURIComponent(top.CKLang.LJCut_WizardNotice + '<br /><a href="#" lj-cmd="LJCut">' + top.CKLang.LJCut_WizardNoticeLink + '</a>')
		}
	};

	var ljUsers = {};
	var execFromEditor;

	function createNote(editor) {
		var timer,
			state,
			currentData,
			tempData,
			noteNode = document.createElement('lj-note'),
			isIE = typeof(document.body.style.opacity) != 'string';

		var animate = (function() {
			var fps = 60,
				totalTime = 100,
				steps = totalTime * fps / 1000,
				timeOuts = [],
				type,
				parentContainer = document.getElementById('draft-container') || document.body;

			function apply() {
				var data = timeOuts.shift();
				var currentStep = (type ? data.time / totalTime : -(data.time / totalTime - 1)).toFixed(1);

				if (!timeOuts.length) {
					currentStep = type ? 1 : 0;
				}

				if (isIE) {
					noteNode.style.filter = (currentStep >= 1) ? null : 'progid:DXImageTransform.Microsoft.Alpha(opacity=' + (currentStep * 100) + ')';
				} else {
					noteNode.style.opacity = currentStep;
				}

				if (currentStep == 0 && noteNode && noteNode.parentNode) {
					noteNode.parentNode.removeChild(noteNode);
				}
			}

			return function(animateType) {
				type = animateType;

				if (type && noteNode.parentNode) {
					if (isIE) {
						noteNode.style.filter = null;
					} else {
						noteNode.style.opacity = 1;
					}
				} else {
					for (var i = 1; i <= steps; i++) {
						var time = Math.floor(1000 / fps) * i;
						timeOuts.push({
							time: time,
							timer: setTimeout(apply, time)
						});
					}
				}

				parentContainer.appendChild(noteNode);
				noteNode.style.marginTop = -noteNode.offsetHeight / 2 + 'px';
				noteNode.style.marginLeft = -noteNode.offsetWidth / 2 + 'px';
			}
		})();

		noteNode.className = 'note-popup';

		noteNode.onmouseout = function() {
			if (!currentData || !currentData.cmd) {
				CKEDITOR.note.hide();
			}
		};

		noteNode.onmouseover = function() {
			if (timer && !state) {
				state = 1;
				clearTimeout(timer);
				timer = null;
			}
		};

		if (isIE) {
			noteNode.style.filter = 'progid:DXImageTransform.Microsoft.Alpha(opacity=0)';
		} else {
			noteNode.style.opacity = 0;
		}

		function callCmd() {
			var cmd = this.getAttribute('lj-cmd');
			if (currentData.hasOwnProperty(cmd)) {
				ljTagsData[cmd].node = currentData[cmd].node;
				var selection = new CKEDITOR.dom.selection(editor.document);
				selection.selectElement(ljTagsData[cmd].node);
				execFromEditor = true;
				editor.execCommand(cmd);
				CKEDITOR.note.hide(true);
			}
			return false;
		}

		function applyNote() {
			if (!window.switchedRteOn) {
				CKEDITOR.note.hide(true);
			}
			if (state) {
				currentData = tempData;
				tempData = null;

				var html = '';
				for (var cmd in currentData) {
					if (currentData.hasOwnProperty(cmd)) {
						html += '<div class="noteItem">' + currentData[cmd].content + '</div>';
					}
				}

				noteNode.innerHTML = decodeURIComponent(html);

				var links = noteNode.getElementsByTagName('a');
				for (var i = 0, l = links.length; i < l; i++) {
					var link = links[i];
					if (ljTagsData.hasOwnProperty(link.getAttribute('lj-cmd'))) {
						link.onclick = callCmd;
					}
				}
			} else {
				currentData = null;
			}

			animate(state);

			timer = null;
		}

		CKEDITOR.note = {
			show: function(data, isNow) {
				if ((!isNow && data == tempData) || window.swi) {
					return;
				}

				if (timer) {
					clearTimeout(timer);
					timer = null;
				}

				state = 1;

				tempData = data;

				isNow === true ? applyNote() : timer = setTimeout(applyNote, 1000);
			},
			hide: function(isNow) {
				if (state) {
					state = 0;

					if (timer) {
						clearTimeout(timer);
						timer = null;
					}

					if (noteNode.parentNode) {
						isNow === true ? applyNote() : timer = setTimeout(applyNote, 500);
					}
				}
			}
		};
	}

	CKEDITOR.plugins.add('livejournal', {
		init: function(editor) {
			function onClickFrame(evt) {
				if (this.$ != editor.document.$) {
					this.frameElement.addClass('lj-cut-selected');
					new CKEDITOR.dom.selection(editor.document).selectElement(this.frameElement);
				}

				evt.data.getKey() == 1 && evt.data.preventDefault();
			}

			function onKeyUp(evt) {
				if (evt.data.getKey() == 46) {
					var ranges = new CKEDITOR.dom.selection(editor.document).getRanges();
					var length = ranges.length;
					while (length--) {
						ranges[length].deleteContents();
					}
				}
			}

			function onLoadFrame() {
				var win = this.$.contentWindow;
				var doc = win.document;
				if (win.frameElement.getAttribute('lj-cmd') && doc.body.scrollHeight) {
					this.setStyle('height', doc.body.scrollHeight + 'px');
				}

				var body = new CKEDITOR.dom.element.get(doc.body);
				body.on('dblclick', onDoubleClick);
				body.on('click', onClickFrame);
				body.on('keyup', onKeyUp);

				doc = new CKEDITOR.dom.element.get(doc);

				doc.frameElement = body.frameElement = this;
			}

			function updateFrames() {
				execFromEditor = false;
				var frames = editor.document.getElementsByTag('iframe');
				var length = frames.count();

				while (length--) {
					var iFrameCss = 'widht: 100%; margin: 0; padding 0; overflow-y: hidden;',
						frame = frames.getItem(length),
						cmd = frame.getAttribute('lj-cmd'),
						frameWin = frame.$.contentWindow,
						doc = frameWin.document,
						ljStyle = frame.getAttribute('lj-style');

					if (ljStyle) {
						iFrameCss += ljStyle;
					}

					frame.removeListener('load', onLoadFrame);
					frame.on('load', onLoadFrame);
					doc.open();
					doc.write('<!DOCTYPE html><html style="' + iFrameCss + '"><head><style type="text/css">' + styleSheet + '</style></head><body style="' + iFrameCss + '" ' + (cmd ? ('lj-cmd="' + cmd + '"') : '') + '>' + decodeURIComponent(frame.getAttribute('lj-content') || '&nbsp;') + '</body></html>');
					doc.close();
				}
			}

			function findLJTags(evt) {
				var noteData,
					isSelection = evt.name == 'selectionChange' || evt.name == 'click',
					target = evt.data.element || evt.data.getTarget(),
					node,
					command;

				if (editor.onSwitch === true) {
					delete editor.onSwitch;
					return;
				}

				if (evt.name == 'click' && (evt.data.getKey() == 1 || evt.data.$.button == 0)) {
					evt.data.preventDefault();
				}

				if (target.type != 1) {
					target = target.getParent();
				}

				node = target;

				if (isSelection) {
					var frames = editor.document.getElementsByTag('iframe');
					for (var i = 0, l = frames.count(); i < l; i++) {
						frames.getItem(i).removeClass('lj-cut-selected');
					}

					if (node.is('iframe')) {
						node.addClass('lj-cut-selected');
					}
				}

				do {
					var attr = node.getAttribute('lj-cmd');

					if (!attr && node.type == 1) {
						var parent = node.getParent();
						if (node.is('img') && parent.getParent() && !parent.getParent().hasAttribute('lj:user')) {
							attr = 'image';
							node.setAttribute('lj-cmd', attr);
						} else if (node.is('a') && !parent.hasAttribute('lj:user')) {
							attr = 'LJLink';
							node.setAttribute('lj-cmd', attr);
						}
					}

					if (attr && ljTagsData.hasOwnProperty(attr)) {
						if (isSelection) {
							ljTagsData[attr].node = node;
							editor.getCommand(attr).setState(CKEDITOR.TRISTATE_ON);
						}
						(noteData || (noteData = {}))[attr] = {
							content: ljTagsData[attr].html,
							node: node
						};
					}
				} while (node = node.getParent());

				if (isSelection) {
					for (command in ljTagsData) {
						if (ljTagsData.hasOwnProperty(command) && (!noteData || !noteData.hasOwnProperty(command))) {
							delete ljTagsData[command].node;
							editor.getCommand(command).setState(CKEDITOR.TRISTATE_OFF);
						}
					}
				}

				noteData ? CKEDITOR.note.show(noteData) : CKEDITOR.note.hide();
			}

			editor.dataProcessor.toHtml = function(html, fixForBody) {
				html = html.replace(/(<lj [^>]+)(?!\/)>/gi, '$1 />').replace(/(<lj-map[^>]+)(?!\/)>/gi, '$1 />').replace(/(<lj-template[^>]*)(?!\/)>/gi, '$1 />').replace(/<((?!br)[^\s>]+)([^>]*?)\/>/gi, '<$1$2></$1>').replace(/<lj-poll.*?>[\s\S]*?<\/lj-poll>/gi,
					function(ljtags) {
						var poll = new Poll(ljtags);
						return '<iframe class="lj-poll" frameborder="0" allowTransparency="true" ' + 'lj-cmd="LJPollLink" lj-data="' + poll.outputLJtags() + '" lj-content="' + poll.outputHTML() + '"></iframe>';
					}).replace(/<lj-embed(.*?)>([\s\S]*?)<\/lj-embed>/gi, function(result, attrs, data) {
						return '<iframe' + attrs + ' class="lj-embed" lj-data="' + encodeURIComponent(data) + '" frameborder="0" allowTransparency="true"></iframe>';
					});

				if (!$('event_format').checked) {
					html = html.replace(/(<lj-raw.*?>)([\s\S]*?)(<\/lj-raw>)/gi,
						function(result, open, content, close) {
							return open + content.replace(/\n/g, '') + close;
						}).replace(/\n/g, '<br />');
				}

				html = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, html, fixForBody);
				if (CKEDITOR.env.ie) {
					html = '<xml:namespace ns="livejournal" prefix="lj" />' + html;
				}
				return html;
			};

			editor.dataProcessor.toDataFormat = function(html, fixForBody) {
				html = CKEDITOR.htmlDataProcessor.prototype.toDataFormat.call(this, html, fixForBody);

				if (!$('event_format').checked) {
					html = html.replace(/<br\s*\/>/gi, '\n');
				}

				html = html.replace(/\t/g, ' ');

				return html;
			};

			editor.dataProcessor.writer.indentationChars = '';
			editor.dataProcessor.writer.lineBreakChars = '';

			function onDoubleClick(evt) {
				var node = evt.data.element || evt.data.getTarget();

				if (node.type != 1) {
					node = node.getParent();
				}

				while (node) {
					var cmdName = node.getAttribute('lj-cmd');
					if (ljTagsData.hasOwnProperty(cmdName)) {
						var cmd = editor.getCommand(cmdName);
						if (cmd.state == CKEDITOR.TRISTATE_ON) {
							var selection = new CKEDITOR.dom.selection(editor.document);
							ljTagsData[cmdName].node = node.is('body') ? new CKEDITOR.dom.element.get(node.getWindow().$.frameElement) : node;
							selection.selectElement(ljTagsData[cmdName].node);
							evt.data.dialog = '';
							execFromEditor = true;
							cmd.exec();
							break;
						}
					}

					node = node.getParent();
				}
			}

			var styleSheet = '';

			CKEDITOR.ajax.load(editor.config.contentsCss, function(data) {
				styleSheet = data;
			});

			editor.on('selectionChange', findLJTags);
			editor.on('doubleclick', onDoubleClick);
			editor.on('afterCommandExec', updateFrames);
			editor.on('dialogHide', updateFrames);
			editor.on('dataReady', function() {
				if (!CKEDITOR.note) {
					createNote(editor);
				}

				editor.document.on('click', findLJTags);
				editor.document.on('mouseout', CKEDITOR.note.hide);
				editor.document.on('mouseover', findLJTags);
				editor.document.getBody().on('keyup', onKeyUp);
				updateFrames();
			});

			//////////  LJ User Button //////////////
			var url = top.Site.siteroot + '/tools/endpoints/ljuser.bml';

			editor.addCommand('LJUserLink', {
				exec: function(editor) {
					var userName = '',
						selection = new CKEDITOR.dom.selection(editor.document),
						LJUser = ljTagsData.LJUserLink.node,
						currentUserName;

					if (LJUser) {
						CKEDITOR.note && CKEDITOR.note.hide(true);
						currentUserName = ljTagsData.LJUserLink.node.getElementsByTag('b').getItem(0).getText();
						userName = prompt(top.CKLang.UserPrompt, currentUserName);
					} else if (selection.getType() == 2) {
						userName = selection.getSelectedText();
					}

					if (userName == '') {
						userName = prompt(top.CKLang.UserPrompt, userName);
					}

					if (!userName || currentUserName == userName) {
						return;
					}

					parent.HTTPReq.getJSON({
						data: parent.HTTPReq.formEncoded({
							username: userName
						}),
						method: 'POST',
						url: url,
						onData: function(data) {
							if (data.error) {
								alert(data.error);
								return;
							}
							if (!data.success) {
								return;
							}
							data.ljuser = data.ljuser.replace('<span class="useralias-value">*</span>', '');

							ljUsers[userName] = data.ljuser;

							var tmpNode = new CKEDITOR.dom.element.createFromHtml(data.ljuser);
							tmpNode.setAttribute('lj-cmd', 'LJUserLink');

							if (LJUser) {
								LJUser.$.parentNode.replaceChild(tmpNode.$, LJUser.$);
							} else {
								editor.insertElement(tmpNode);
							}
						}
					});
				}
			});

			editor.ui.addButton('LJUserLink', {
				label: top.CKLang.LJUser,
				command: 'LJUserLink'
			});

			//////////  LJ Image Button //////////////
			editor.ui.addButton('image', {
				label: editor.lang.common.imageButton,
				command: 'image'
			});

			if (window.ljphotoEnabled) {
				editor.addCommand('LJImage_beta', {
					exec: function(editor) {
						jQuery('#updateForm').photouploader({
							type: 'upload'
						}).photouploader('show').bind('htmlready', function (event) {
								var html = event.htmlStrings;
								for (var i = 0, l = html.length; i < l; i++) {
									editor.insertElement(new CKEDITOR.dom.element.createFromHtml(html[i], editor.document));
								}
							});
					},
					editorFocus: false
				});

				editor.ui.addButton('LJImage_beta', {
					label: editor.lang.common.imageButton,
					command: 'LJImage_beta'
				});
			}

			//////////  LJ Link Button //////////////
			editor.addCommand('LJLink', {
				exec: function(editor) {
					!execFromEditor && this.state == CKEDITOR.TRISTATE_ON ? editor.execCommand('unlink') : editor.openDialog('link');
					CKEDITOR.note && CKEDITOR.note.hide(true);
				},
				editorFocus: false
			});

			editor.ui.addButton('LJLink', {
				label: editor.lang.link.toolbar,
				command: 'LJLink'
			});

			//////////  LJ Embed Media Button //////////////
			editor.addCommand('LJEmbedLink', {
				exec: function() {
					top.LJ_IPPU.textPrompt(top.CKLang.LJEmbedPromptTitle, top.CKLang.LJEmbedPrompt, doEmbed, {
						width: '350px'
					});
				}
			});

			editor.ui.addButton('LJEmbedLink', {
				label: top.CKLang.LJEmbed,
				command: 'LJEmbedLink'
			});

			editor.addCss('.lj-embed {' + 'background: #CCCCCC url(' + CKEDITOR.getUrl(this.path + 'images/placeholder_flash.png') + ') no-repeat center center;' + 'border: 1px dotted #000000;' + 'height: 80px;' + 'width: 100%;' + '}');

			function doEmbed(content) {
				if (content && content.length) {
					if (window.switchedRteOn) {
						var iframe = new CKEDITOR.dom.element('iframe', editor.document);
						iframe.setAttribute('lj-data', encodeURIComponent(content));
						iframe.setAttribute('class', 'lj-embed');
						iframe.setAttribute('frameBorder', 0);
						iframe.setAttribute('allowTransparency', 'true');
						editor.insertElement(iframe);
						updateFrames();
					}
				}
			}

			//////////  LJ Cut Button //////////////
			editor.addCss('.lj-cut {\
				display: block;\
				margin: 5px 0;\
				width: 100%;\
				cursor: pointer;\
				height: 9px!important;\
				background-color: #FFF;\
				border: 0 dashed #BCBCBC;\
				background: url(/js/ck/images/ljcut.png) no-repeat 0 0;\
			}');
			editor.addCss('.lj-cut-open {\
				background-position: 0 2px;\
				border-width: 0 0 1px;\
			}');
			editor.addCss('.lj-cut-close {\
				border-width: 1px 0 0;\
				background-position: 0 -8px;\
			}');
			editor.addCss('.lj-cut-selected {\
				background-color: #C4E0F7;\
				border: 1px solid #6EA9DF;\
			}');


			editor.addCommand('LJCut', {
				exec: function() {
					var text,
						ljCutNode = ljTagsData.LJCut.node;

					if (ljCutNode) {
						if (text = prompt(top.CKLang.CutPrompt, ljCutNode.getAttribute('text') || top.CKLang.ReadMore)) {
							if (text == top.CKLang.ReadMore) {
								ljCutNode.removeAttribute('text');
							} else {
								ljCutNode.setAttribute('text', text);
							}
						}
					} else {
						if (text = prompt(top.CKLang.CutPrompt, top.CKLang.ReadMore)) {
							var selection = new CKEDITOR.dom.selection(editor.document),
								ranges = selection.getRanges();

							var startContainer = selection.getRanges()[0].getTouchedStartNode();

							if(startContainer){
								if (startContainer.type == 1 && !startContainer.is('body')) {
									startContainer = startContainer.getPrevious();
								}
							} else {
								startContainer = editor.document.getBody();
							}

							var fragment = new CKEDITOR.dom.documentFragment(editor.document);

							var iframeOpen = new CKEDITOR.dom.element('iframe', editor.document);
							iframeOpen.setAttribute('lj-cmd', 'LJCut');
							iframeOpen.addClass('lj-cut lj-cut-open');
							iframeOpen.setAttribute('frameBorder', 0);
							iframeOpen.setAttribute('allowTransparency', 'true');
							fragment.append(iframeOpen);

							for (var i = 0, l = ranges.length; i < l; i++) {
								var range = ranges[i];
								fragment.append(range.extractContents());
							}

							var iframeClose = new CKEDITOR.dom.element('iframe', editor.document);
							iframeClose.addClass('lj-cut lj-cut-close');
							iframeClose.setAttribute('lj-cmd', 'LJCut');
							iframeClose.setAttribute('frameBorder', 0);
							iframeClose.setAttribute('allowTransparency', 'true');
							fragment.append(iframeClose);

							if (text != top.CKLang.ReadMore) {
								iframeOpen.setAttribute('text', text);
							}

							if (startContainer.is && startContainer.is('body')) {
								startContainer.append(fragment, true);
							} else {
								fragment.insertAfterNode(startContainer);
							}
						}

						CKEDITOR.note && CKEDITOR.note.hide(true);
					}
				},
				editorFocus: false
			});

			editor.ui.addButton('LJCut', {
				label: top.CKLang.LJCut,
				command: 'LJCut'
			});

			//////////  LJ Justify //////////////
			(function() {
				function getAlignment(element, useComputedState) {
					useComputedState = useComputedState === undefined || useComputedState;

					var align,
						LJLike = ljTagsData.LJLike.node;
					if (LJLike) {
						var attr = element.getAttribute('lj-style');
						align = attr ? attr.replace(/text-align:\s*(left|right|center)/i, '$1') : 'left';
					} else if (useComputedState) {
						align = element.getComputedStyle('text-align');
					} else {
						while (!element.hasAttribute || !( element.hasAttribute('align') || element.getStyle('text-align') )) {
							var parent = element.getParent();
							if (!parent) {
								break;
							}
							element = parent;
						}
						align = element.getStyle('text-align') || element.getAttribute('align') || '';
					}

					align && ( align = align.replace(/-moz-|-webkit-|start|auto/i, '') );

					!align && useComputedState && ( align = element.getComputedStyle('direction') == 'rtl' ? 'right' : 'left' );

					return align;
				}

				function onSelectionChange(evt) {
					if (evt.editor.readOnly) {
						return;
					}

					var command = evt.editor.getCommand(this.name),
						element = evt.data.element,
						cmd = element.type == 1 && element.hasAttribute('lj-cmd') && element.getAttribute('lj-cmd');
					if (cmd == 'LJLike') {
						command.state = (getAlignment(element, editor.config.useComputedState) == this.value) ? CKEDITOR.TRISTATE_ON : CKEDITOR.TRISTATE_OFF;
					} else if (!element || element.type != 1 || element.getName() == 'body' || element.getName() == 'iframe') {
						command.state = CKEDITOR.TRISTATE_OFF;
					} else {
						command.state = getAlignment(element, editor.config.useComputedState) == this.value ? CKEDITOR.TRISTATE_ON : CKEDITOR.TRISTATE_OFF;
					}

					command.fire('state');
				}

				function justifyCommand(editor, name, value) {
					this.name = name;
					this.value = value;

					var classes = editor.config.justifyClasses;
					if (classes) {
						switch (value) {
							case 'left' :
								this.cssClassName = classes[0];
								break;
							case 'center' :
								this.cssClassName = classes[1];
								break;
							case 'right' :
								this.cssClassName = classes[2];
								break;
						}

						this.cssClassRegex = new RegExp('(?:^|\\s+)(?:' + classes.join('|') + ')(?=$|\\s)');
					}
				}

				function onDirChanged(e) {
					var editor = e.editor;

					var range = new CKEDITOR.dom.range(editor.document);
					range.setStartBefore(e.data.node);
					range.setEndAfter(e.data.node);

					var walker = new CKEDITOR.dom.walker(range),
						node;

					while (( node = walker.next() )) {
						if (node.type == CKEDITOR.NODE_ELEMENT) {
							// A child with the defined dir is to be ignored.
							if (!node.equals(e.data.node) && node.getDirection()) {
								range.setStartAfter(node);
								walker = new CKEDITOR.dom.walker(range);
								continue;
							}

							// Switch the alignment.
							var classes = editor.config.justifyClasses;
							if (classes) {
								// The left align class.
								if (node.hasClass(classes[ 0 ])) {
									node.removeClass(classes[ 0 ]);
									node.addClass(classes[ 2 ]);
								}
								// The right align class.
								else if (node.hasClass(classes[ 2 ])) {
									node.removeClass(classes[ 2 ]);
									node.addClass(classes[ 0 ]);
								}
							}

							// Always switch CSS margins.
							var style = 'text-align';
							var align = node.getStyle(style);

							if (align == 'left') {
								node.setStyle(style, 'right');
							} else if (align == 'right') {
								node.setStyle(style, 'left');
							}
						}
					}
				}

				justifyCommand.prototype = {
					exec : function(editor) {
						var selection = editor.getSelection(),
							enterMode = editor.config.enterMode;

						if (!selection) {
							return;
						}

						var bookmarks = selection.createBookmarks();

						if (ljTagsData.LJLike.node) {
							ljTagsData.LJLike.node.setAttribute('lj-style', 'text-align: ' + this.value);
						} else {
							var ranges = selection.getRanges(true);

							var cssClassName = this.cssClassName,
								iterator,
								block;

							var useComputedState = editor.config.useComputedState;
							useComputedState = useComputedState === undefined || useComputedState;

							for (var i = ranges.length - 1; i >= 0; i--) {
								var range = ranges[i];
								var encloseNode = range.getEnclosedNode();
								if (encloseNode && encloseNode.is('iframe')) {
									return;
								}

								iterator = range.createIterator();
								iterator.enlargeBr = enterMode != CKEDITOR.ENTER_BR;
								while (( block = iterator.getNextParagraph(enterMode == CKEDITOR.ENTER_P ? 'p' : 'div') )) {
									block.removeAttribute('align');
									block.removeStyle('text-align');

									// Remove any of the alignment classes from the className.
									var className = cssClassName && ( block.$.className = CKEDITOR.tools.ltrim(block.$.className.replace(this.cssClassRegex, '')) );

									var apply = ( this.state == CKEDITOR.TRISTATE_OFF ) && ( !useComputedState || ( getAlignment(block, true) != this.value ) );

									if (cssClassName) {
										// Append the desired class name.
										if (apply) {
											block.addClass(cssClassName);
										} else if (!className) {
											block.removeAttribute('class');
										}
									} else if (apply) {
										block.setStyle('text-align', this.value);
									}
								}

							}
						}

						editor.focus();
						editor.forceNextSelectionCheck();
						selection.selectBookmarks(bookmarks);
					}
				};

				var left = new justifyCommand(editor, 'LJJustifyLeft', 'left'),
					center = new justifyCommand(editor, 'LJJustifyCenter', 'center'),
					right = new justifyCommand(editor, 'LJJustifyRight', 'right');

				editor.addCommand('LJJustifyLeft', left);
				editor.addCommand('LJJustifyCenter', center);
				editor.addCommand('LJJustifyRight', right);

				editor.ui.addButton('LJJustifyLeft', {
					label : editor.lang.justify.left,
					command : 'LJJustifyLeft'
				});
				editor.ui.addButton('LJJustifyCenter', {
					label : editor.lang.justify.center,
					command : 'LJJustifyCenter'
				});
				editor.ui.addButton('LJJustifyRight', {
					label : editor.lang.justify.right,
					command : 'LJJustifyRight'
				});

				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, left));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, right));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, center));
				editor.on('dirChanged', onDirChanged);
			})();

			//////////  LJ Poll Button //////////////
			if (top.canmakepoll) {
				var currentPoll;

				editor.addCss('.lj-poll {' + 'width:100%;' + 'border: #000 1px dotted;' + 'background-color: #d2d2d2;' + 'font-style: italic;' + '}');

				CKEDITOR.dialog.add('LJPollDialog', function() {
					var isAllFrameLoad = 0, okButtonNode, questionsWindow, setupWindow;

					var onLoadPollPage = function() {
						if (this.removeListener) {
							this.removeListener('load', onLoadPollPage);
						}
						if (isAllFrameLoad && okButtonNode) {
							currentPoll = new Poll(ljTagsData.LJPollLink.node && decodeURIComponent(ljTagsData.LJPollLink.node.getAttribute('lj-data')), questionsWindow.document, setupWindow.document, questionsWindow.Questions);

							questionsWindow.ready(currentPoll);
							setupWindow.ready(currentPoll);

							okButtonNode.style.display = 'block';
							CKEDITOR.note && CKEDITOR.note.hide(true);
						} else {
							isAllFrameLoad++;
						}
					};

					var buttonsDefinition = [new CKEDITOR.ui.button({
						type: 'button',
						id: 'LJPoll_Ok',
						label: editor.lang.common.ok,
						onClick: function(evt) {
							evt.data.dialog.hide();
							var poll = new Poll(currentPoll, questionsWindow.document, setupWindow.document, questionsWindow.Questions);
							var pollSource = poll.outputHTML();
							var pollLJTags = poll.outputLJtags();

							if (pollSource.length > 0) {
								if (ljTagsData.LJPollLink.node) {
									ljTagsData.LJPollLink.node.setAttribute('lj-content', pollSource);
									ljTagsData.LJPollLink.node.setAttribute('lj-data', pollLJTags);
								} else {
									var node = new CKEDITOR.dom.element('iframe', editor.document);
									node.setAttribute('lj-content', pollSource);
									node.setAttribute('lj-cmd', 'LJPollLink');
									node.setAttribute('lj-data', pollLJTags);
									node.setAttribute('class', 'lj-poll');
									node.setAttribute('frameBorder', 0);
									node.setAttribute('allowTransparency', 'true');
									editor.insertElement(node);
								}
								ljTagsData.LJPollLink.node = null;
								updateFrames();
							}
						}
					}), CKEDITOR.dialog.cancelButton];

					CKEDITOR.env.mac && buttonsDefinition.reverse();

					return {
						title: top.CKLang.Poll_PollWizardTitle,
						width: 420,
						height: 270,
						resizable: false,
						onShow: function() {
							if (isAllFrameLoad) {
								currentPoll = new Poll(ljTagsData.LJPollLink.node && unescape(ljTagsData.LJPollLink.node.getAttribute('data')), questionsWindow.document, setupWindow.document, questionsWindow.Questions);

								questionsWindow.ready(currentPoll);
								setupWindow.ready(currentPoll);
							}
						},
						contents: [
							{
								id: 'LJPoll_Setup',
								label: 'Setup',
								padding: 0,
								elements: [
									{
										type: 'html',
										html: '<iframe src="/tools/ck_poll_setup.bml" allowTransparency="true" frameborder="0" style="width:100%; height:320px;"></iframe>',
										onShow: function(data) {
											if (!okButtonNode) {
												(okButtonNode = document.getElementById(data.sender.getButton('LJPoll_Ok').domId).parentNode).style.display = 'none';
											}
											var iframe = this.getElement('iframe');
											setupWindow = iframe.$.contentWindow;
											if (setupWindow.ready) {
												onLoadPollPage();
											} else {
												iframe.on('load', onLoadPollPage);
											}
										}
									}
								]
							},
							{
								id: 'LJPoll_Questions',
								label: 'Questions',
								padding: 0,
								elements:[
									{
										type: 'html',
										html: '<iframe src="/tools/ck_poll_questions.bml" allowTransparency="true" frameborder="0" style="width:100%; height:320px;"></iframe>',
										onShow: function() {
											var iframe = this.getElement('iframe');
											questionsWindow = iframe.$.contentWindow;
											if (questionsWindow.ready) {
												onLoadPollPage();
											} else {
												iframe.on('load', onLoadPollPage);
											}
										}
									}
								]
							}
						],
						buttons: buttonsDefinition
					};
				});

				editor.addCommand('LJPollLink', new CKEDITOR.dialogCommand('LJPollDialog'));
			} else {
				editor.addCommand('LJPollLink', {
					exec: function() {
						CKEDITOR.note && CKEDITOR.note.show(top.CKLang.Poll_AccountLevelNotice, null, null, true);
					}
				});

				editor.getCommand('LJPollLink').setState(CKEDITOR.TRISTATE_DISABLED);
			}

			editor.ui.addButton('LJPollLink', {
				label: top.CKLang.Poll,
				command: 'LJPollLink'
			});

			//////////  LJ Like Button //////////////
			var buttonsLength = likeButtons.length;
			var dialogContent = '<div class="cke-dialog-likes"><ul class="cke-dialog-likes-list">';
			likeButtons.defaultButtons = [];

			editor.addCss('.lj-like {' + 'width: 100%;' + 'height: 44px !important;' + 'overflow: hidden;' + 'padding: 0;' + 'margin: 0;' + 'background: #D2D2D2;' + 'border: 1px dotted #000;' + '}');

			for (var i = 0; i < buttonsLength; i++) {
				var button = likeButtons[i];
				likeButtons[button.id] = likeButtons[button.abbr] = button;
				likeButtons.defaultButtons.push(button.id);
				dialogContent += button.htmlOpt;
			}

			dialogContent += '</ul><p class="cke-dialog-likes-faq">' + window.faqLink + '</p></div>';

			var countChanges = 0, ljLikeDialog, ljLikeInputs;

			function onChangeLike() {
				var command = editor.getCommand('LJLike');
				if (command.state == CKEDITOR.TRISTATE_OFF) {
					this.$.checked ? countChanges++ : countChanges--;
					ljLikeDialog.getButton('LJLike_Ok').getElement()[countChanges == 0 ? 'addClass' : 'removeClass']('btn-disabled');
				}
			}

			CKEDITOR.dialog.add('LJLikeDialog', function() {
				var buttonsDefinition = [new CKEDITOR.ui.button({
					type: 'button',
					id: 'LJLike_Ok',
					label: editor.lang.common.ok,
					onClick: function() {
						if (ljLikeDialog.getButton('LJLike_Ok').getElement().hasClass('btn-disabled')) {
							return false;
						}

						var attr = [],
							likeHtml = '<span class="lj-like-wrapper">',
							likeNode = ljTagsData.LJLike.node;

						for (var i = 0; i < buttonsLength; i++) {
							var button = likeButtons[i];
							var input = document.getElementById('like-' + button.abbr);
							var currentBtn = likeNode && likeNode.getAttribute('buttons');
							if ((input && input.checked) || (currentBtn && !button.htmlOpt && (currentBtn.indexOf(button.abbr) + 1 || currentBtn.indexOf(button.id) + 1))) {
								attr.push(button.id);
								likeHtml += button.html;
							}
						}

						likeHtml += '</span>';
						if (attr.length) {
							if (likeNode) {
								ljTagsData.LJLike.node.setAttribute('buttons', attr.join(','));
								ljTagsData.LJLike.node.setAttribute('lj-content', encodeURIComponent(likeHtml));
							} else {
								likeNode = new CKEDITOR.dom.element('iframe', editor.document);
								likeNode.setAttribute('class', 'lj-like');
								likeNode.setAttribute('buttons', attr.join(','));
								likeNode.setAttribute('lj-content', encodeURIComponent(likeHtml));
								likeNode.setAttribute('lj-cmd', 'LJLike');
								likeNode.setAttribute('frameBorder', 0);
								likeNode.setAttribute('allowTransparency', 'true');
								editor.insertElement(likeNode);
							}
						} else if (likeNode) {
							ljTagsData.LJLike.node.remove();
						}

						ljLikeDialog.hide();
					}
				}), CKEDITOR.dialog.cancelButton];

				CKEDITOR.env.mac && buttonsDefinition.reverse();

				return {
					title: top.CKLang.LJLike_name,
					width: 145,
					height: window.isSupUser ? 180 : 145,
					resizable: false,
					contents: [
						{
							id: 'LJLike_Options',
							elements: [
								{
									type: 'html',
									html: dialogContent
								}
							]
						}
					],
					onShow: function() {
						CKEDITOR.note && CKEDITOR.note.hide(true);
						var command = editor.getCommand('LJLike');
						var i = countChanges = 0,
							isOn = command.state == CKEDITOR.TRISTATE_ON,
							buttons = ljTagsData.LJLike.node && ljTagsData.LJLike.node.getAttribute('buttons');

						for (; i < buttonsLength; i++) {
							var isChecked = buttons ? !!(buttons.indexOf(likeButtons[i].abbr) + 1 || buttons.indexOf(likeButtons[i].id) + 1) : true;

							var input = document.getElementById('like-' + likeButtons[i].abbr);

							if (input) {
								if (isChecked && !isOn) {
									countChanges++;
								}

								input.checked = isChecked;
							}
						}

						if (countChanges > 0) {
							ljLikeDialog.getButton('LJLike_Ok').getElement().removeClass('btn-disabled');
						}
					},
					onLoad: function() {
						ljLikeDialog = this;
						ljLikeInputs = ljLikeDialog.parts.contents.getElementsByTag('input');
						for (var i = 0; i < buttonsLength; i++) {
							var item = ljLikeInputs.getItem(i);
							item && item.on('click', onChangeLike);
						}
					},
					buttons: buttonsDefinition
				}
			});

			editor.addCommand('LJLike', new CKEDITOR.dialogCommand('LJLikeDialog'));

			editor.ui.addButton('LJLike', {
				label: top.CKLang.LJLike_name,
				command: 'LJLike'
			});

			//////////  LJ Map Button & LJ Iframe //////////////
			editor.addCss('.lj-map, .lj-iframe {' + 'width: 100%;' + 'overflow: hidden;' + 'min-height: 13px;' + 'margin-top: 20px;' + 'background: #D2D2D2;' + 'border: 1px dotted #000;' + 'text-align: center;' + '}');
		},
		afterInit: function(editor) {
			var dataProcessor = editor.dataProcessor;

			function createLJCut(element) {
				var openFrame = new CKEDITOR.htmlParser.element('iframe');
				openFrame.attributes['class'] = 'lj-cut lj-cut-open';
				openFrame.attributes['lj-cmd'] = 'LJCut';
				openFrame.attributes['frameBorder'] = 0;
				openFrame.attributes['allowTransparency'] = 'true';

				if (element.attributes.hasOwnProperty('text')) {
					openFrame.attributes.text = element.attributes.text;
				}

				element.children.unshift(openFrame);

				var closeFrame = new CKEDITOR.htmlParser.element('iframe');
				closeFrame.attributes['class'] = 'lj-cut lj-cut-close';
				closeFrame.attributes['frameBorder'] = 0;
				closeFrame.attributes['allowTransparency'] = 'true';
				element.children.push(closeFrame);

				delete element.name;
			}

			dataProcessor.dataFilter.addRules({
				elements: {
					'lj-like': function(element) {
						var attr = [];

						var fakeElement = new CKEDITOR.htmlParser.element('iframe');
						fakeElement.attributes['class'] = 'lj-like';
						if (element.attributes.hasOwnProperty('style')) {
							fakeElement.attributes['lj-style'] = element.attributes.style;
						}
						fakeElement.attributes['lj-cmd'] = 'LJLike';
						fakeElement.attributes['lj-content'] = '<span class="lj-like-wrapper">';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						var currentButtons = element.attributes.buttons && element.attributes.buttons.split(',') || likeButtons.defaultButtons;

						var length = currentButtons.length;
						for (var i = 0; i < length; i++) {
							var buttonName = currentButtons[i].replace(/^\s*([a-z]{2,})\s*$/i, '$1');
							var button = likeButtons[buttonName];
							if (button) {
								fakeElement.attributes['lj-content'] += encodeURIComponent(button.html);
								attr.push(buttonName);
							}
						}

						fakeElement.attributes['lj-content'] += '</span>';

						fakeElement.attributes.buttons = attr.join(',');
						return fakeElement;
					},
					'lj': (function() {
						function updateUser(name) {
							var ljTags = editor.document.getElementsByTag('lj');

							for (var i = 0, l = ljTags.count(); i < l; i++) {
								var ljTag = ljTags.getItem(i);

								var userName = ljTag.getAttribute('user');
								var userTitle = ljTag.getAttribute('title');
								if (name == (userTitle ? userName + ':' + userTitle : userName)) {
									var newLjTag = new CKEDITOR.dom.element.createFromHtml(ljUsers[name], editor.document);
									newLjTag.setAttribute('lj-cmd', 'LJUserLink');
									ljTag.insertBeforeMe(newLjTag);
									ljTag.remove();
								}
							}

							editor.removeListener('dataReady', updateUser);
						}

						return function(element) {
							var ljUserName = element.attributes.user;
							if (!ljUserName || !ljUserName.length) {
								return;
							}

							var ljUserTitle = element.attributes.title;
							var cacheName = ljUserTitle ? ljUserName + ':' + ljUserTitle : ljUserName;

							if (ljUsers.hasOwnProperty(cacheName)) {
								var ljTag = (new CKEDITOR.htmlParser.fragment.fromHtml(ljUsers[cacheName])).children[0];

								ljTag.attributes['lj-cmd'] = 'LJUserLink';
								return ljTag;
							} else {
								var postData = {
									username: ljUserName
								};

								if (ljUserTitle) {
									postData.usertitle = ljUserTitle;
								}

								HTTPReq.getJSON({
									data: HTTPReq.formEncoded(postData),
									method: 'POST',
									url: Site.siteroot + '/tools/endpoints/ljuser.bml',
									onError: function(err) {
										alert(err + ' "' + ljUserName + '"');
									},
									onData: function(data) {
										if (data.error) {
											return alert(data.error + ' "' + username + '"');
										}

										if (!data.success) {
											return;
										}

										ljUsers[cacheName] = data.ljuser;

										data.ljuser = data.ljuser.replace('<span class="useralias-value">*</span>', '');

										if (editor.document) {
											updateUser(cacheName);
										} else {
											editor.on('dataReady', function() {
												updateUser(cacheName);
											});
										}
									}
								});
							}
						};
					})(),
					'lj-map': function(element) {
						var fakeElement = new CKEDITOR.htmlParser.element('iframe');
						fakeElement.attributes.style = 'width:' + (isNaN(element.attributes.width) ? 500 : element.attributes.width) + 'px;' + 'height:' + (isNaN(element.attributes.height) ? 350 : element.attributes.height) + 'px;';

						fakeElement.attributes['lj-url'] = element.attributes.url ? encodeURIComponent(element.attributes.url) : '';
						fakeElement.attributes['class'] = 'lj-map';
						fakeElement.attributes['lj-content'] = '<p class="lj-map">map</p>';
						fakeElement.attributes['lj-style'] = ' height: 100%; text-align: center;';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						return fakeElement;
					},
					'lj-repost': function(element) {
						var fakeElement = new CKEDITOR.htmlParser.element('input');
						fakeElement.attributes.type = 'button';
						fakeElement.attributes.value = (element.attributes && element.attributes.button) || top.CKLang.LJRepost_Value;
						fakeElement.attributes['class'] = 'lj-repost';
						return fakeElement;
					},
					'lj-raw': function(element) {
						element.name = 'lj:raw';
					},
					'lj-wishlist': function(element) {
						element.name = 'lj:wishlist';
					},
					'lj-template': function(element) {
						element.name = 'lj:template';
						element.children.length = 0;
					},
					'lj-cut': createLJCut,
					'iframe': function(element) {
						if (element.attributes['class'] && element.attributes['class'].indexOf('lj-') + 1 == 1) {
							return element;
						}
						var fakeElement = new CKEDITOR.htmlParser.element('iframe');
						fakeElement.attributes.style = 'width:' + (isNaN(element.attributes.width) ? 500 : element.attributes.width) + 'px;' + 'height:' + (isNaN(element.attributes.height) ? 350 : element.attributes.height) + 'px;';

						fakeElement.attributes['lj-url'] = element.attributes.src ? encodeURIComponent(element.attributes.src) : '';
						fakeElement.attributes['class'] = 'lj-iframe';
						fakeElement.attributes['lj-content'] = '<p class="lj-iframe">iframe</p>';
						fakeElement.attributes['lj-style'] = ' height: 100%; text-align: center;';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						return fakeElement;
					},
					a: function(element) {
						if (element.parent.attributes && !element.parent.attributes['lj:user']) {
							element.attributes['lj-cmd'] = 'LJLink';
						}
					},
					img: function(element) {
						var parent = element.parent.parent;
						if (!parent || !parent.attributes || !parent.attributes['lj:user']) {
							element.attributes['lj-cmd'] = 'image';
						}
					},
					div: function(element) {
						if (element.attributes['class'] == 'lj-cut') {
							createLJCut(element);
						}
					}
				}
			}, 5);

			dataProcessor.htmlFilter.addRules({
				elements: {
					iframe: function(element) {
						var newElement = element;
						var className = /lj-[a-z]+/i.exec(element.attributes['class']);
						if (className) {
							className = className[0];
						} else {
							return element;
						}
						switch (className) {
							case 'lj-like':
								newElement = new CKEDITOR.htmlParser.element('lj-like');
								newElement.attributes.buttons = element.attributes.buttons;
								if (element.attributes.hasOwnProperty('lj-style')) {
									newElement.attributes.style = element.attributes['lj-style'];
								}
								newElement.isEmpty = true;
								newElement.isOptionalClose = true;
								break;
							case 'lj-embed':
								newElement = new CKEDITOR.htmlParser.element('lj-embed');
								newElement.attributes.id = element.attributes.id;
								if (element.attributes.hasOwnProperty('source_user')) {
									newElement.attributes.source_user = element.attributes.source_user;
								}
								newElement.children = new CKEDITOR.htmlParser.fragment.fromHtml(decodeURIComponent(element.attributes['lj-data'])).children;
								newElement.isOptionalClose = true;
								break;
							case 'lj-map':
								newElement = new CKEDITOR.htmlParser.element('lj-map');
								newElement.attributes.url = decodeURIComponent(element.attributes['lj-url']);
								element.attributes.style && (element.attributes.style + ';').replace(/([a-z-]+):(.*?);/gi, function(result, name, value) {
									newElement.attributes[name.toLowerCase()] = parseInt(value);
								});

								newElement.isOptionalClose = newElement.isEmpty = true;
								break;
							case 'lj-iframe':
								newElement = new CKEDITOR.htmlParser.element('iframe');
								newElement.attributes.src = decodeURIComponent(element.attributes['lj-url']);
								element.attributes.style && (element.attributes.style + ';').replace(/([a-z-]+):(.*?);/gi, function(result, name, value) {
									newElement.attributes[name.toLowerCase()] = parseInt(value);
								});
								newElement.attributes.frameBorder = 0;
								break;
							case 'lj-poll':
								newElement = new CKEDITOR.htmlParser.fragment.fromHtml(decodeURIComponent(element.attributes['lj-data'])).children[0];
								break;
							case 'lj-cut':
								if (element.attributes['class'].indexOf('lj-cut-open') + 1) {
									var node = element.next;
									newElement = new CKEDITOR.htmlParser.element('lj-cut');

									if (element.attributes.hasOwnProperty('text')) {
										newElement.attributes.text = element.attributes.text;
									}

									while (node) {
										if (node.name == 'iframe') {
											var ljCutclassName = node.attributes['class'];
											if (ljCutclassName.indexOf('lj-cut-close') + 1) {
												newElement.next = node;
												break;
											} else if (ljCutclassName.indexOf('lj-cut-open') + 1) {
												newElement.next = node;
												break;
											}
										}

										node.parent.children.remove(node);
										newElement.add(node);
										var next = node.next;
										node.next = null;
										node = next;
									}
								} else {
									newElement = false;
								}
								break;
							default:
								if (!element.children.length) {
									newElement = false;
								}
						}

						return newElement;
					},
					span: function(element) {
						var userName = element.attributes['lj:user'];
						if (userName) {
							var ljUserNode = new CKEDITOR.htmlParser.element('lj');
							ljUserNode.attributes.user = userName;

							try {
								var userTitle = element.children[1].children[0].children[0].value;
							} catch(e) {
								return false;
							}

							if (userTitle && userTitle != userName) {
								ljUserNode.attributes.title = userTitle;
							}

							ljUserNode.isOptionalClose = ljUserNode.isEmpty = true;
							return ljUserNode;
						} else if (element.attributes.style == 'display: none;' || !element.children.length) {
							return false;
						}
					},
					input: function(element) {
						if (element.attributes['class'] == 'lj-repost') {
							var newElement = new CKEDITOR.htmlParser.element('lj-repost');
							if (element.attributes.value != top.CKLang.LJRepost_Value) {
								newElement.attributes.button = element.attributes.value;
							}
							newElement.isOptionalClose = newElement.isEmpty = true;
							return newElement;
						}
					},
					div: function(element) {
						if (!element.children.length) {
							return false;
						}
					},
					'lj:template': function(element) {
						element.name = 'lj-template';
						element.isOptionalClose = element.isEmpty = true;
					},
					'lj:raw': function(element) {
						element.name = 'lj-raw';
					},
					'lj:wishlist': function(element) {
						element.name = 'lj-wishlist';
					}
				},
				attributes: {
					'lj-cmd': function() {
						return false;
					},
					'contenteditable': function() {
						return false;
					}
				}
			});
		},

		requires: ['fakeobjects', 'domiterator']
	});

})();
