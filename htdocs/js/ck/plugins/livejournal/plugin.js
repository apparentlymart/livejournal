(function() {
	var CKLang = CKEDITOR.lang[CKEDITOR.lang.detect()] || {};
	jQuery.extend(CKLang, LJ.pageVar('rtedata'));

	if (Site.page.ljpost) {
		CKEDITOR.styleText = Site.statprefix + '/js/ck/contents_new.css?t=' + Site.version;
	} else {
		CKEDITOR.styleText = Site.statprefix + '/js/ck/contents.css?t=' + Site.version;
	}
	

	var likeButtons = [
		{
			label: CKLang.LJLike_button_repost,
			id:'repost',
			abbr: 'rp',
			checked: true,
			html: '<span class="lj-like-item rp">' + CKLang.LJLike_button_repost + '</span>',
			htmlOpt: '<li class="like-rp"><input type="checkbox" id="like-rp" /><label for="like-rp">' + CKLang.LJLike_button_repost + '</label></li>'
		},
		{
			label: CKLang.LJLike_button_facebook,
			id: 'facebook',
			abbr: 'fb',
			checked: true,
			html: '<span class="lj-like-item fb">' + CKLang.LJLike_button_facebook + '</span>',
			htmlOpt: '<li class="like-fb"><input type="checkbox" id="like-fb" /><label for="like-fb">' + CKLang.LJLike_button_facebook + '</label></li>'
		},
		{
			label: CKLang.LJLike_button_twitter,
			id: 'twitter',
			abbr: 'tw',
			checked: true,
			html: '<span class="lj-like-item tw">' + CKLang.LJLike_button_twitter + '</span>',
			htmlOpt: '<li class="like-tw"><input type="checkbox" id="like-tw" /><label for="like-tw">' + CKLang.LJLike_button_twitter + '</label></li>'
		},
		{
			label: CKLang.LJLike_button_google,
			id: 'google',
			abbr: 'go',
			checked: true,
			html: '<span class="lj-like-item go">' + CKLang.LJLike_button_google + '</span>',
			htmlOpt: '<li class="like-go"><input type="checkbox" id="like-go" /><label for="like-go">' + CKLang.LJLike_button_google + '</label></li>'
		},
		{
			label: CKLang.LJLike_button_vkontakte,
			id: 'vkontakte',
			abbr: 'vk',
			checked: Site.remote_is_sup ? true : false,
			html: '<span class="lj-like-item vk">' + CKLang.LJLike_button_vkontakte + '</span>',
			htmlOpt: Site.remote_is_sup? '<li class="like-vk"><input type="checkbox" id="like-vk" /><label for="like-vk">' + CKLang.LJLike_button_vkontakte + '</label></li>' : ''
		},
		{
			label: CKLang.LJLike_button_give,
			id: 'livejournal',
			abbr: 'lj',
			checked: false,
			html: '<span class="lj-like-item lj">' + CKLang.LJLike_button_give + '</span>',
			htmlOpt: '<li class="like-lj"><input type="checkbox" id="like-lj" /><label for="like-lj">' + CKLang.LJLike_button_give + '</label></li>'
		}
	];

	var ljTagsData = {
		LJPollLink: {
			html: encodeURIComponent(CKLang.Poll_PollWizardNotice + '<br /><a href="#" lj-cmd="LJPollLink">' + CKLang.Poll_PollWizardNoticeLink + '</a>')
		},
		LJLike: {
			html: encodeURIComponent(CKLang.LJLike_WizardNotice + '<br /><a href="#" lj-cmd="LJLike">' + CKLang.LJLike_WizardNoticeLink + '</a>')
		},
		LJUserLink: {
			html: encodeURIComponent(CKLang.LJUser_WizardNotice + '<br /><a href="#" lj-cmd="LJUserLink">' + CKLang.LJUser_WizardNoticeLink + '</a>')
		},
		LJLink2: {
			html: encodeURIComponent(CKLang.LJLink_WizardNotice + '<br /><a href="#" lj-cmd="LJLink2">' + CKLang.LJLink_WizardNoticeLink + '</a>')
		},
		image: {
			html: encodeURIComponent(CKLang.LJImage_WizardNotice + '<br /><a href="#" lj-cmd="image">' + CKLang.LJImage_WizardNoticeLink + '</a>')
		},
		LJCut: {
			html: encodeURIComponent(CKLang.LJCut_WizardNotice + '<br /><a href="#" lj-cmd="LJCut">' + CKLang.LJCut_WizardNoticeLink + '</a>')
		},
		LJSpoiler: {
			html: encodeURIComponent(CKLang.LJSpoiler_WizardNotice + '<br /><a href="#" lj-cmd="LJSpoiler">' + CKLang.LJSpoiler_WizardNoticeLink + '</a>')
		},
		LJEmbedLink: {

		},
		LJMap: {

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
			var fps = 60, totalTime = 100, steps = totalTime * fps / 1000, timeOuts = [], type, parentContainer = document.getElementById('draft-container') || document.body;

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
				timer = clearTimeout(timer);
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
				if ((!isNow && data == tempData) || !window.switchedRteOn) {
					return;
				}

				if (timer) {
					timer = clearTimeout(timer);
				}

				state = 1;
				tempData = data;
				isNow === true ? applyNote() : timer = setTimeout(applyNote, 1000);
			},
			hide: function(isNow) {
				if (state) {
					state = 0;

					if (timer) {
						timer = clearTimeout(timer);
					}

					if (noteNode.parentNode) {
						isNow === true ? applyNote() : timer = setTimeout(applyNote, 500);
					}
				}
			}
		};
	}

	var dtd = CKEDITOR.dtd;

	dtd.$block['lj-template'] = 1;
	dtd.$block['lj-raw'] = 1;
	dtd.$block['lj-cut'] = 1;
	dtd.$block['lj-spoiler'] = 1;
	dtd.$block['lj-poll'] = 1;
	dtd.$block['lj-repost'] = 1;
	dtd.$block['lj-pq'] = 1;
	dtd.$block['lj-pi'] = 1;
	dtd.$nonEditable['lj-template'] = 1;

	dtd['lj-template'] = {};
	dtd['lj-map'] = {};
	dtd['lj-repost'] = {};
	dtd['lj-raw'] = dtd.div;

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

	CKEDITOR.tools.extend(dtd['lj-cut'] = {}, dtd.$block);
	CKEDITOR.tools.extend(dtd['lj-spoiler'] = {}, dtd.$block);

	CKEDITOR.tools.extend(dtd['lj-cut'], dtd.$inline);
	CKEDITOR.tools.extend(dtd['lj-spoiler'], dtd.$inline);

	CKEDITOR.tools.extend(dtd.div, dtd.$block);
	CKEDITOR.tools.extend(dtd.$body, dtd.$block);

	delete dtd['lj-cut']['lj-cut'];

	CKEDITOR.plugins.add('livejournal', {
		init: function(editor) {
			// The editor event listeners
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

			function onClickFrame(evt) {
				if (this.$ != editor.document.$) {
					this.$.className = (this.frame.getAttribute('lj-class') || '') + ' lj-selected';
					if (this.getAttribute('lj-cmd') == 'LJPollLink') {
						this.frame.setStyle('height', this.getDocument().$.body.scrollHeight + 'px');
					}
					new CKEDITOR.dom.selection(editor.document).selectElement(this.frame);
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
				var win = this.$.contentWindow, doc = win.document, iframeBody = new CKEDITOR.dom.element.get(doc.body);

				if (iframeBody.on) {
					iframeBody.on('dblclick', onDoubleClick);
					iframeBody.on('click', onClickFrame);
					iframeBody.on('keyup', onKeyUp);

					if (this.getAttribute('lj-cmd') == 'LJPollLink' && this.hasAttribute('style')) {
						doc.body.className = 'lj-poll lj-poll-open';
					}
				}

				doc = new CKEDITOR.dom.element.get(doc);
				doc.frame = iframeBody.frame = this;
			}

			function updateFrames() {
				var frames = editor.document.getElementsByTag('iframe'), length = frames.count(), frame, cmd, frameWin, doc, ljStyle;
				execFromEditor = false;

				while (length--) {
					frame = frames.getItem(length), cmd = frame.getAttribute('lj-cmd'), frameWin = frame.$.contentWindow, doc = frameWin.document, ljStyle = frame.getAttribute('lj-style') || '';
					frame.removeListener('load', onLoadFrame);
					frame.on('load', onLoadFrame);
					doc.open();
					doc.write('<!DOCTYPE html>' +
						'<html style="' + ljStyle + '">' +
							'<head><link rel="stylesheet" href="' + CKEDITOR.styleText + '" /></head>' +
							'<body scroll="no" class="' + (frame.getAttribute('lj-class') || '') + '" style="' + ljStyle + '" ' + (cmd ? ('lj-cmd="' + cmd + '"') : '') + '>'
								+ decodeURIComponent(frame.getAttribute('lj-content') || '') +
							'</body>' +
						'</html>');
					doc.close();
				}
			}

			function findLJTags(evt) {
				if (editor.onSwitch === true) {
					delete editor.onSwitch;
					return;
				}

				var noteData, isClick = evt.name == 'click', isSelection = evt.name == 'selectionChange' || isClick, target = evt.data.element || evt.data.getTarget(), node, command;

				if (isClick && (evt.data.getKey() == 1 || evt.data.$.button == 0)) {
					evt.data.preventDefault();
				}

				if (target.type != 1) {
					target = target.getParent();
				}

				node = target;

				if (isSelection) {
					var frames = editor.document.getElementsByTag('iframe'), frame, body;

					if (isClick && node.is('iframe')) {
						body = node.$.contentWindow.document.body;
						body.className = (node.getAttribute('lj-class') || '') + ' lj-selected';
						if (node.getAttribute('lj-cmd') == 'LJPollLink') {
							node.setStyle('height', body.scrollHeight + 'px');
						}
					}

					for (var i = 0, l = frames.count(); i < l; i++) {
						frame = frames.getItem(i);
						if (frame.$ != node.$) {
							body = frame.$.contentWindow.document.body;
							body.className = frame.getAttribute('lj-class') || '';
							if (frame.getAttribute('lj-cmd') == 'LJPollLink' && body.className.indexOf('lj-poll') != -1 ) {
								frame.removeAttribute('style');
							}
						}
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
							attr = 'LJLink2';
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

			// Configure editor
			(function () {
				function closeTag(result) {
					return result.slice(-2) == '/>' ? result : result.slice(0, -1) + '/>';
				}

				function createPoll(ljtags) {
					var poll = new Poll(ljtags),
						content = "<div class='lj-poll-inner lj-rtebox-inner'>" + poll.outputHTML() + "</div>";
					return '<iframe class="lj-poll-wrap lj-rtebox" lj-class="lj-poll" frameborder="0" lj-cmd="LJPollLink" allowTransparency="true" ' + 'lj-data="' + poll.outputLJtags() + '" lj-content="' + content + '"></iframe>';
				}

				function createUneditablePoll(ljtags, pollId) {
					var content = "<div class='lj-poll-inner lj-rtebox-inner'>Poll id: " + pollId + "</div>";
					return '<iframe class="lj-poll-wrap lj-poll-wrap-done lj-rtebox" lj-class="lj-poll" frameborder="0" lj-cmd="LJPollLink" allowTransparency="true" ' + 'lj-data="' + escape(ljtags) + '" lj-content="' + content + '" data-disabledPoll="true"></iframe>';
				}

				function createEmbed(result, attrs, data) {
					var content = "<div class='lj-embed-inner lj-rtebox-inner'>Embed video</div>";
					return '<iframe class="lj-embed-wrap lj-rtebox" lj-class="lj-embed" frameborder="0" lj-cmd="LJEmbedLink" allowTransparency="true" lj-data="' + encodeURIComponent(data) + '"' + attrs + 'lj-content="' + content + '"></iframe>';
				}

				function createLJRaw(result, open, content, close) {
					return open + content.replace(/\n/g, '') + close;
				}

				function createRepost(result, firstAttr, secondAttr, content) {
					var buttonTitle = firstAttr || secondAttr || CKLang.LJRepost_Value;
					var text = content.replace(/"/g, '&quot;');

					content = text + ('<br /><input type="button" value="' + buttonTitle + '" />').replace(/"/g, '&quot;');

					return '<iframe class="lj-repost-wrap" lj-class="lj-repost" frameborder="0" allowTransparency="true" lj-text="' + text + '" lj-button="' + buttonTitle + '" lj-content="' + content + '"></iframe>';
				}

				editor.dataProcessor.toHtml = function(html, fixForBody) {
					html = html.replace(/<lj [^>]*?>/gi, closeTag)
						.replace(/<lj-map [^>]*?>/gi, closeTag)
						.replace(/<lj-template[^>]*?>/gi, closeTag)
						.replace(/(<lj-cut[^>]*?)\/>/gi, '$1>')
						.replace(/<((?!br)[^\s>]+)([^>]*?)\/>/gi, '<$1$2></$1>')
						.replace(/<lj-poll.*?>[\s\S]*?<\/lj-poll>/gi, createPoll)
						.replace(/<lj-poll-([0-9]+)>/gi, createUneditablePoll)
						.replace(/<lj-repost\s*(?:button\s*=\s*(?:"([^"]*?)")|(?:"([^']*?)"))?.*?>([\s\S]*?)<\/lj-repost>/gi, createRepost)
						.replace(/<lj-embed(.*?)>([\s\S]*?)<\/lj-embed>/gi, createEmbed);

					if (!$('event_format').checked) {
						html = html.replace(/(<lj-raw.*?>)([\s\S]*?)(<\/lj-raw>)/gi, createLJRaw);

						if (!window.switchedRteOn) {
							html = html.replace(/\n/g, '<br />');
						}
					}

					html = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, html, fixForBody);

					if (CKEDITOR.env.ie) {
						html = '<xml:namespace ns="livejournal" prefix="lj" />' + html;
					}

					return html;
				};
			})();

			editor.dataProcessor.toDataFormat = function(html, fixForBody) {
				html = CKEDITOR.htmlDataProcessor.prototype.toDataFormat.call(this, html, fixForBody);

				if (!$('event_format').checked) {
					html = html.replace(/<br\s*\/>/gi, '\n');
				}

				return html.replace(/\t/g, ' ');
			};

			editor.dataProcessor.writer.indentationChars = '';
			editor.dataProcessor.writer.lineBreakChars = '';

			editor.on('selectionChange', findLJTags);
			editor.on('doubleclick', onDoubleClick);
			editor.on('afterCommandExec', updateFrames);
			editor.on('dialogHide', updateFrames);

			editor.on('dataReady', function() {
				if (!CKEDITOR.note) {
					createNote(editor);
				}

				if (CKEDITOR.env.ie) {
					editor.document.getBody().on('dragend', updateFrames);
					editor.document.getBody().on('paste', function () {
						setTimeout(updateFrames, 0);
					});
				}

				editor.document.on('click', findLJTags);
				editor.document.on('mouseout', CKEDITOR.note.hide);
				editor.document.on('mouseover', findLJTags);
				editor.document.getBody().on('keyup', onKeyUp);
				updateFrames();
			});

			// LJ Buttons

			// LJ User
			(function () {
				var url = top.Site.siteroot + '/tools/endpoints/ljuser.bml',
					button = 'LJUserLink';

				function onData(data, userName, LJUser) {
					if (data.error) {
						LiveJournal.run_hook('incorrect_user');
						return;
					}

					if (data.success) {
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

				}

				var hooked = false;
				editor.addCommand('LJUserLink', {
					exec: function(editor) {
						var userName = '',
							selection = new CKEDITOR.dom.selection(editor.document),
							LJUser = ljTagsData.LJUserLink.node,
							currentUserName;

						function checkInsert(username) {
							parent.HTTPReq.getJSON({
								data: parent.HTTPReq.formEncoded({
									username: username
								}),
								method: 'POST',
								url: url,
								onData: function (data) {
									onData(data, username, ljTagsData.LJUserLink.node);
								}
							});
						}

						if (!hooked) {
							var lj = LJUser;
							LiveJournal.register_hook('user_response', function(user) {
								checkInsert(user);
							});
							hooked = true;
						}

						if (LJUser) {
							CKEDITOR.note && CKEDITOR.note.hide(true);
							currentUserName = ljTagsData.LJUserLink.node.getElementsByTag('b').getItem(0).getText();

							LiveJournal.run_hook('rteButton', 'user', jQuery('.cke_button_' + button), {
								user: currentUserName
							});

							return;
						} else if (selection.getType() == 2) {
							userName = selection.getSelectedText();
						}

						if (userName == '') {
							LiveJournal.run_hook('rteButton', 'user', jQuery('.cke_button_' + button));
							return;
						}

						if (!userName || currentUserName == userName) {
							return;
						}

						checkInsert(userName, LJUser);
					}
				});

				editor.ui.addButton('LJUserLink', {
					label: CKLang.LJUser,
					command: 'LJUserLink'
				});
			})();

			// LJ Image
			(function() {
				var button = "LJImage";

				if (window.ljphotoEnabled && window.ljphotoMigrationStatus === LJ.getConst('LJPHOTO_MIGRATION_NONE')) {
					editor.ui.addButton('image', {
						label: CKLang.LJImage_Title,
						command: 'image'
					});
				} else {
					editor.addCommand(button, {
						exec: function () {
							jQuery('.b-updatepage-event-section').editor('handleImageUpload', 'upload');
						},
						editorFocus: false
					});

					editor.ui.addButton('image', {
						label: CKLang.LJImage_Title,
						command: button
					});
				}
			})();

			// LJ Embed
			(function () {
				var button = "LJEmbedLink",
					widget = 'video';

				function insertEmbed(content) {
					var iframe = new CKEDITOR.dom.element('iframe', editor.document);

					iframe.setAttribute('lj-data', encodeURIComponent(content));
					iframe.setAttribute('lj-content', encodeURIComponent("<div class='lj-embed-inner lj-rtebox-inner'>Embed video</div>"));
					iframe.setAttribute('lj-class', 'lj-embed');
					iframe.setAttribute('lj-cmd', button);
					iframe.setAttribute('class', 'lj-embed-wrap lj-rtebox');
					iframe.setAttribute('frameBorder', 0);
					iframe.setAttribute('allowTransparency', 'true');

					editor.insertElement(iframe);
					updateFrames();
				}

				LiveJournal.register_hook(widget + '_response', function(content) {
					insertEmbed(content);
				});

				editor.addCommand(button, {
					exec: function() {
						var node = ljTagsData[button].node;

						if (node) {
							LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), {
								defaultText: node && decodeURIComponent(node.getAttribute('lj-data')),
								editMode: true
							});
						} else {
							LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button));
						}

					}
				});

				editor.ui.addButton(button, {
					label: CKLang.LJEmbed,
					command: button
				});
			})();

			function doubleFrameCommand (tagName, cmdName, promptData) {
				var text,
					ljNode = ljTagsData[cmdName].node;

				if (ljNode) {
					if (text = promptData.skip || prompt(promptData.title, ljNode.getAttribute('text') || promptData.text)) {
						if (text == promptData.text) {
							ljNode.removeAttribute('text');
						} else {
							ljNode.setAttribute('text', text);
						}
					}
				} else {
					if (text = promptData.skip || prompt(promptData.title, promptData.text)) {
						editor.focus();

						var selection = new CKEDITOR.dom.selection(editor.document),
							ranges = selection.getRanges(),
							iframeOpen = new CKEDITOR.dom.element('iframe', editor.document),
							iframeClose = iframeOpen.clone();

						iframeOpen.setAttribute('lj-cmd', cmdName);
						iframeOpen.setAttribute('lj-class', tagName + ' ' + tagName + '-open');
						iframeOpen.setAttribute('class', tagName + '-wrap');
						iframeOpen.setAttribute('frameBorder', 0);
						iframeOpen.setAttribute('allowTransparency', 'true');
						if (text != promptData.text) {
							iframeOpen.setAttribute('text', text);
						}

						iframeClose.setAttribute('lj-class', tagName + ' ' + tagName + '-close');
						iframeClose.setAttribute('class', tagName + '-wrap');
						iframeClose.setAttribute('frameBorder', 0);
						iframeClose.setAttribute('allowTransparency', 'true');

						var range = ranges[0];
						selection.lock();

						var br = new CKEDITOR.dom.element('br', editor.document),
							firstBR = br.clone(),
							lastBR = br.clone();

						var fragment = new CKEDITOR.dom.documentFragment(editor.document);
						fragment.append(br.clone());
						fragment.append(iframeOpen);
						fragment.append(firstBR);

						if (range.collapsed === false) {
							for (var i = 0, l = ranges.length; i < l; i++) {
								// https://jira.sup.com/browse/LJSV-2328
								// https://jira.sup.com/browse/LJSUP-13130
								if (selection.getSelectedElement()) {
									ranges[i].enlarge( CKEDITOR.ENLARGE_ELEMENT );
								}

								fragment.append(ranges[i].extractContents());
							}
						}

						fragment.append(lastBR);
						editor.insertElement(iframeClose);
						br.clone().insertAfter(iframeClose);
						iframeClose.insertBeforeMe(fragment);

						range.setStart(firstBR, 0);
						range.setEnd(lastBR, 0);
						selection.unlock();

						selection.selectRanges(ranges);

						editor.fire('updateSnapshot');
						updateFrames();
					}

					CKEDITOR.note && CKEDITOR.note.hide(true);
				}

			}

			// LJ Map
			(function() {
				var button = "LJMap",
					widget = "map";

				LiveJournal.register_hook('map_response', function(text) {
					var iframe = new CKEDITOR.dom.element('iframe', editor.document);

					var width = 800,
						height = 600,
						frameStyle = "", bodyStyle = "";

					if (!isNaN(width)) {
						frameStyle += 'width:' + width + 'px;';
						bodyStyle += 'width:' + (width - 2) + 'px;';
					}

					if (!isNaN(height)) {
						frameStyle += 'height:' + height + 'px;';
						bodyStyle += 'height:' + (height - 2) + 'px;';
					}

					var node = ljTagsData[button].node;
					if (node) {
						node.setAttributes({
							'lj-url': text
						});
					} else {
						iframe.setAttributes({
							'lj-url': text,
							'class': 'lj-map-wrap lj-rtebox',

							'lj-content': '<div class="lj-map-inner lj-rtebox-inner"><p class="lj-map">map</p></div>',

							'lj-cmd': 'LJMap',
							'lj-class': 'lj-map',
							'frameborder': 0,
							'allowTransparency': 'true',

							'style': frameStyle,
							'lj-style': bodyStyle
						});
						editor.insertElement(iframe);
					}
					updateFrames();
				});

				editor.addCommand(button, {
					exec: function() {
						var node = ljTagsData[button].node;

						LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), {
							defaultText: node ? node.getAttribute('lj-url') : '',
							editMode: node? true : false
						});
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJMap_Title,
					command: button
				});
			})();

			// LJ Cut
			(function() {
				var button = "LJCut",
					widget = "cut";

				LiveJournal.register_hook('cut_response', function(text) {
					doubleFrameCommand('lj-cut', button, {
						title: CKLang.LJCut_PromptTitle,
						text: CKLang.LJCut_PromptText,

						skip: text
					});
				});

				editor.addCommand('LJCut', {
					exec: function() {
						var node = ljTagsData[button].node;

						LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), {
							defaultText: node ? node.getAttribute('text') : '',
							editMode: node? true : false
						});
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJCut_Title,
					command: button
				});
			})();

			// LJ Spoiler
			(function() {
				var button = "LJSpoiler",
					widget = "spoiler";

				LiveJournal.register_hook('spoiler_response', function(text) {
					doubleFrameCommand('lj-spoiler', button, {
						title: CKLang.LJCut_PromptTitle,
						text: CKLang.LJCut_PromptText,

						skip: text
					});
				});

				editor.addCommand(button, {
					exec: function() {
						var node = ljTagsData[button].node;

						LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), {
							defaultText: node ? node.getAttribute('text') : '',
							editMode: node? true : false
						});
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJSpoiler_Title,
					command: button
				});
			})();

			// LJ Justify
			(function() {
				function getAlignment(element, useComputedState) {
					useComputedState = useComputedState === undefined || useComputedState;

					var align, LJLike = ljTagsData.LJLike.node;
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

					var command = evt.editor.getCommand(this.name), element = evt.data.element;
					if ((element.type == 1 && element.hasAttribute('lj-cmd') && element.getAttribute('lj-cmd')) == 'LJLike') {
						command.state = getAlignment(element, editor.config.useComputedState) == this.value ? CKEDITOR.TRISTATE_ON : CKEDITOR.TRISTATE_OFF;
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

					var walker = new CKEDITOR.dom.walker(range), node;

					while (( node = walker.next() )) {
						if (node.type == CKEDITOR.NODE_ELEMENT) {
							var style = 'text-align', classes = editor.config.justifyClasses;

							if (!node.equals(e.data.node) && node.getDirection()) {
								range.setStartAfter(node);
								walker = new CKEDITOR.dom.walker(range);
								continue;
							}

							if (classes) {
								if (node.hasClass(classes[ 0 ])) {
									node.removeClass(classes[ 0 ]);
									node.addClass(classes[ 2 ]);
								} else if (node.hasClass(classes[ 2 ])) {
									node.removeClass(classes[ 2 ]);
									node.addClass(classes[ 0 ]);
								}
							}

							switch (node.getStyle(style)) {
								case 'left':
									node.setStyle(style, 'right');
									break;
								case 'right':
									node.setStyle(style, 'left');
									break;
							}
						}
					}
				}

				justifyCommand.prototype = {
					exec : function(editor) {
						var selection = editor.getSelection(), enterMode = editor.config.enterMode;

						if (!selection) {
							return;
						}

						var bookmarks = selection.createBookmarks();

						if (ljTagsData.LJLike.node) {
							ljTagsData.LJLike.node.setAttribute('lj-style', 'text-align: ' + this.value);
						} else {
							var ranges = selection.getRanges(true);

							var cssClassName = this.cssClassName, iterator, block;

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

									var className = cssClassName && ( block.$.className = CKEDITOR.tools.ltrim(block.$.className.replace(this.cssClassRegex, '')) );

									var apply = ( this.state == CKEDITOR.TRISTATE_OFF ) && ( !useComputedState || ( getAlignment(block, true) != this.value ) );

									if (cssClassName) {
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

				var left = new justifyCommand(editor, 'LJJustifyLeft', 'left'), center = new justifyCommand(editor, 'LJJustifyCenter', 'center'), right = new justifyCommand(editor, 'LJJustifyRight', 'right');

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

			// LJ Poll
			(function() {
				var button = 'LJPollLink';

				LiveJournal.register_hook('poll_response', function(ljData) {
					var poll = new Poll(ljData), // Poll.js
						content = "<div class='lj-poll-inner lj-rtebox-inner'>" + poll.outputHTML() + '</div>',
						pollLJTags = poll.outputLJtags();

					var node = ljTagsData[button].node;
					if (node) {
						node.setAttribute('lj-content', content);
						node.setAttribute('lj-data', pollLJTags);
						node.removeAttribute('style');
					} else {
						node = new CKEDITOR.dom.element('iframe', editor.document);
						node.setAttribute('lj-content', content);
						node.setAttribute('lj-cmd', 'LJPollLink');
						node.setAttribute('lj-data', pollLJTags);
						node.setAttribute('lj-class', 'lj-poll lj-rtebox');
						node.setAttribute('class', 'lj-poll-wrap');
						node.setAttribute('frameBorder', 0);
						node.setAttribute('allowTransparency', 'true');
						editor.insertElement(node);
					}

					updateFrames();
				});

				editor.addCommand(button, {
					exec: function(editor) {
						var node = ljTagsData.LJPollLink.node;

						if (node) {
							LiveJournal.run_hook('rteButton', 'poll', jQuery('.cke_button_' + button), {
								ljData: decodeURIComponent(node.getAttribute('lj-data')),
								editMode: true,
								disabled: node && (node.getAttribute('data-disabledPoll') ? true : false)
							});
						} else {
							LiveJournal.run_hook('rteButton', 'poll', jQuery('.cke_button_' + button));
						}
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJPoll_Title,
					command: button
				});
			})();

			// LJ Like
			(function() {
				var button = 'LJLike',
					widget = "like";

				likeButtons.defaultButtons = [];
				for (var i = 0; i < likeButtons.length; i++) {
					btn = likeButtons[i];
					// WTF
					likeButtons[btn.id] = likeButtons[btn.abbr] = btn;
					likeButtons.defaultButtons.push(btn.id);
				}

				LiveJournal.register_hook('like_response', function(buttons) {
					var attr = [],
						likeHtml = [],
						isDefaultSet = typeof buttons === 'string';

					for (var i = 0, btn; i < likeButtons.length; i++) {
						btn = likeButtons[i];

						if ((isDefaultSet && btn.checked) || buttons.indexOf(btn.id) != -1) {
							attr.push(btn.id);
							likeHtml.push(btn.html);
						}
					}

					var likeNode = ljTagsData[button].node,
						content = encodeURIComponent('<div class="lj-rtebox-inner lj-like-inner"><span class="lj-like-wrapper">' + likeHtml.join('') + '</span></div>');

					if (likeNode) {
						likeNode.setAttribute('buttons', attr.join(','));
						likeNode.setAttribute('lj-content', content);
						likeNode.removeAttribute('defaults');
					} else {
						likeNode = new CKEDITOR.dom.element('iframe', editor.document);
						likeNode.setAttribute('lj-class', 'lj-like');
						likeNode.setAttribute('class', 'lj-like-wrap lj-rtebox');
						likeNode.setAttribute('buttons', attr.join(','));
						likeNode.setAttribute('lj-content', content);
						likeNode.setAttribute('lj-cmd', 'LJLike');
						likeNode.setAttribute('frameBorder', 0);
						likeNode.setAttribute('allowTransparency', 'true');

						likeNode.setAttribute('defaults', isDefaultSet);

						editor.insertElement(likeNode);
					}

					updateFrames();
				});

				editor.addCommand(button, {
					exec: function(editor) {
						var node = ljTagsData[button].node;

						if (node) {
							LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), {
								buttons: node.getAttribute('buttons'),
								editMode: true
							});
						} else {
							LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button));
						}
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJLike_Title,
					command: button
				});
			})();
		},
		afterInit: function(editor) {
			var dataProcessor = editor.dataProcessor;

			function createDoubleFrame(element, tagName, cmdName, attrName) {
				attrName = attrName || 'text';

				var openFrame = new CKEDITOR.htmlParser.element('iframe');
				openFrame.attributes['lj-class'] = tagName + ' ' + tagName + '-open';
				openFrame.attributes['class'] = tagName + '-wrap';
				openFrame.attributes['lj-cmd'] = cmdName;
				openFrame.attributes['frameBorder'] = 0;
				openFrame.attributes['allowTransparency'] = 'true';

				if (element.attributes.hasOwnProperty(attrName)) {
					openFrame.attributes.text = element.attributes[attrName];
				}

				element.children.unshift(openFrame);

				var closeFrame = new CKEDITOR.htmlParser.element('iframe');
				closeFrame.attributes['lj-class'] = tagName + ' ' + tagName + '-close';
				closeFrame.attributes['class'] = tagName + '-wrap';
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
						fakeElement.attributes['lj-class'] = 'lj-like';
						fakeElement.attributes['class'] = 'lj-like-wrap lj-rtebox';
						if (element.attributes.hasOwnProperty('style')) {
							fakeElement.attributes['lj-style'] = element.attributes.style;
						}
						fakeElement.attributes['lj-cmd'] = 'LJLike';
						fakeElement.attributes['lj-content'] = '<div class="lj-rtebox-inner lj-like-inner"><span class="lj-like-wrapper">';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						var currentButtons = element.attributes.buttons && element.attributes.buttons.split(',') || likeButtons.defaultButtons,
							isDefault = element.attributes.buttons ? true : false;

						var length = currentButtons.length;
						for (var i = 0; i < length; i++) {
							var buttonName = currentButtons[i].replace(/^\s*([a-z]{2,})\s*$/i, '$1');
							var button = likeButtons[buttonName];
							if (button && (isDefault || button.checked)) {
								fakeElement.attributes['lj-content'] += encodeURIComponent(button.html);
								attr.push(buttonName);
							}
						}

						if (!element.attributes.buttons) fakeElement.attributes['defaults'] = true;

						fakeElement.attributes['lj-content'] += '</span></div>';

						fakeElement.attributes.buttons = attr.join(',');

						return fakeElement;
					},
					'lj': (function() {
						function updateUser(name) {
							var ljTags = editor.document.getElementsByTag('lj');

							for (var i = 0, l = ljTags.count(); i < l; i++) {
								var ljTag = ljTags.getItem(i);

								if (ljTag) {
									var userName = ljTag.getAttribute('user');
									var userTitle = ljTag.getAttribute('title');
									if (name == (userTitle ? userName + ':' + userTitle : userName)) {
										var newLjTag = new CKEDITOR.dom.element.createFromHtml(ljUsers[name], editor.document);
										newLjTag.setAttribute('lj-cmd', 'LJUserLink');
										ljTag.insertBeforeMe(newLjTag);
										ljTag.remove();
									}
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
											return alert(data.error + ' "' + ljUserName + '"');
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
						var frameStyle = '';
						var bodyStyle = '';
						var width = Number(element.attributes.width);
						var height = Number(element.attributes.height);

						if (!isNaN(width)) {
							frameStyle += 'width:' + width + 'px;';
							bodyStyle += 'width:' + (width - 2) + 'px;';
						}

						if (!isNaN(height)) {
							frameStyle += 'height:' + height + 'px;';
							bodyStyle += 'height:' + (height - 2) + 'px;';
						}

						if (frameStyle.length) {
							fakeElement.attributes['style'] = frameStyle;
							fakeElement.attributes['lj-style'] = bodyStyle;
						}

						fakeElement.attributes['lj-url'] = element.attributes.url ? encodeURIComponent(element.attributes.url) : '';
						fakeElement.attributes['lj-class'] = 'lj-map';
						fakeElement.attributes['class'] = 'lj-map-wrap lj-rtebox';
						fakeElement.attributes['lj-content'] = '<div class="lj-map-inner lj-rtebox-inner"><p class="lj-map">map</p></div>';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						return fakeElement;
					},
					'lj-raw': function(element) {
						element.name = 'lj:raw';
					},
					'lj-wishlist': function(element) {
						element.name = 'lj:wishlist';
					},
					'lj-template': function(element) {
						var fakeElement = new CKEDITOR.htmlParser.element('iframe');
						fakeElement.attributes['lj-class'] = 'lj-template';
						fakeElement.attributes['class'] = 'lj-template-wrap';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';
						fakeElement.attributes['lj-attributes'] = encodeURIComponent(LiveJournal.JSON.stringify(element.attributes));

						return fakeElement;
					},
					'lj-cut': function (element) {
						createDoubleFrame(element, 'lj-cut', 'LJCut');
					},
					'lj-spoiler': function (element) {
						createDoubleFrame(element, 'lj-spoiler', 'LJSpoiler', 'title');
					},
					'iframe': function(element) {
						if (element.attributes['lj-class'] && element.attributes['lj-class'].indexOf('lj-') + 1 == 1) {
							return element;
						}
						var fakeElement = new CKEDITOR.htmlParser.element('iframe'),
							frameStyle = '',
							bodyStyle = '',
							width = Number(element.attributes.width),
							height = Number(element.attributes.height);

						if (!isNaN(width)) {
							frameStyle += 'width:' + width + 'px;';
							bodyStyle += 'width:' + (width - 2) + 'px;';
						}

						if (!isNaN(height)) {
							frameStyle += 'height:' + height + 'px;';
							bodyStyle += 'height:' + (height - 2) + 'px;';
						}

						if (frameStyle.length) {
							fakeElement.attributes['style'] = frameStyle;
							fakeElement.attributes['lj-style'] = bodyStyle;
						}

						fakeElement.attributes['lj-url'] = element.attributes.src ? encodeURIComponent(element.attributes.src) : '';
						fakeElement.attributes['lj-class'] = 'lj-iframe';
						fakeElement.attributes['class'] = 'lj-iframe-wrap lj-rtebox';
						fakeElement.attributes['lj-content'] = '<div class="lj-rtebox-inner"><p class="lj-iframe">iframe</p></div>';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						return fakeElement;
					},
					a: function(element) {
						if (element.parent.attributes && !element.parent.attributes['lj:user']) {
							element.attributes['lj-cmd'] = 'LJLink2';
						}
					},
					img: function(element) {
						var parent = element.parent && element.parent.parent;
						if (!parent || !parent.attributes || !parent.attributes['lj:user']) {
							element.attributes['lj-cmd'] = 'image';
						}
					},
					div: function(element) {
						if (element.attributes['class'] == 'lj-cut') {
							createDoubleFrame(element, 'lj-cut', 'LJCut');
						}
					}
				}
			}, 5);

			dataProcessor.htmlFilter.addRules({
				elements: {
					iframe: function(element) {
						var newElement = element,
							isCanBeNested = false,
							attrName = 'text',
							className = /lj-[a-z]+/i.exec(element.attributes['lj-class']);

						if (className) {
							className = className[0];
						} else {
							return element;
						}
						
						switch (className) {
							case 'lj-like':
								newElement = new CKEDITOR.htmlParser.element('lj-like');

								if (element.attributes.defaults != 'true') {
									newElement.attributes.buttons = element.attributes.buttons;
								}
								
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
							case 'lj-repost':
								newElement = new CKEDITOR.htmlParser.element('lj-repost');
								newElement.attributes.button = element.attributes['lj-button'];
								newElement.children = new CKEDITOR.htmlParser.fragment.fromHtml(element.attributes['lj-text']).children;
							break;
							case 'lj-template':
								newElement = new CKEDITOR.htmlParser.element('lj-template');
								newElement.attributes = LiveJournal.JSON.parse(encodeURIComponent(element.attributes['lj-attributes']));
								newElement.isOptionalClose = newElement.isEmpty = true;
							break;
							case 'lj-spoiler':
								isCanBeNested = true;
								attrName = 'title';
							case 'lj-cut':
								if (element.attributes['lj-class'].indexOf(className + '-open') + 1) {
									var node = element.next,
										index = 0;

									newElement = new CKEDITOR.htmlParser.element(className);

									if (element.attributes.hasOwnProperty('text')) {
										newElement.attributes[attrName] = element.attributes['text'];
									}

									while (node) {
										if (node.name == 'iframe') {
											var DFclassName = node.attributes['lj-class'];
											if (DFclassName.indexOf(className + '-close') + 1) {
												if (isCanBeNested && index) {
													index--;
												} else {
													newElement.next = node;
													break;
												}
											} else if (DFclassName.indexOf(className + '-open') + 1) {
												if (isCanBeNested) {
													index++;
												} else {
													newElement.next = node;
													break;
												}
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
					div: function(element) {
						if (!element.children.length) {
							return false;
						}
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
