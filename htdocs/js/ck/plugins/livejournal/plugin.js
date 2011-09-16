(function() {
	// For IE 8-
	document.namespaces && document.namespaces.add('lj', 'livejournal');

	var dtd = CKEDITOR.dtd;

	dtd.$block['lj:template'] = 1;
	dtd.$block['lj:raw'] = 1;
	dtd.$block['lj:cut'] = 1;

	CKEDITOR.tools.extend(dtd.div, dtd.$block);
	CKEDITOR.tools.extend(dtd.$body, dtd.$block);
	dtd.$nonEditable['lj:template'] = 1;

	dtd['lj:template'] = {};
	dtd['lj:raw'] = dtd.div;
	dtd['lj:cut'] = dtd.div;

	CKEDITOR.dtd.$block['lj-poll'] = 1;
	CKEDITOR.dtd.$block['lj-pq'] = 1;
	CKEDITOR.dtd.$block['lj-pi'] = 1;

	CKEDITOR.dtd['lj-poll'] = {
		'lj-pq': 1
	};

	CKEDITOR.dtd['lj-pq'] = {
		'#': 1,
		'lj-pi': 1
	};

	CKEDITOR.dtd['lj-pi'] = {
		'#': 1
	};

	var likeButtons = [
		{
			label: top.CKLang.LJLike_button_facebook,
			id: 'facebook',
			abbr: 'fb',
			html: '<span class="lj-like-item lj-like-gag fb">' + top.CKLang.LJLike_button_facebook + '</span>',
			htmlOpt: '<li class="like-fb"><input type="checkbox" id="like-fb" /><label for="like-fb">' + top.CKLang
				.LJLike_button_facebook + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_twitter,
			id: 'twitter',
			abbr: 'tw',
			html: '<span class="lj-like-item lj-like-gag tw">' + top.CKLang.LJLike_button_twitter + '</span>',
			htmlOpt: '<li class="like-tw"><input type="checkbox" id="like-tw" /><label for="like-tw">' + top.CKLang
				.LJLike_button_twitter + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_google,
			id: 'google',
			abbr: 'go',
			html: '<span class="lj-like-item lj-like-gag go">' + top.CKLang.LJLike_button_google + '</span>',
			htmlOpt: '<li class="like-go"><input type="checkbox" id="like-go" /><label for="like-go">' + top.CKLang
				.LJLike_button_google + '</label></li>'
		},
		{
			label: top.CKLang.LJLike_button_vkontakte,
			id: 'vkontakte',
			abbr: 'vk',
			html: '<span class="lj-like-item lj-like-gag vk">' + top.CKLang.LJLike_button_vkontakte + '</span>',
			htmlOpt: window
				.isSupUser ? '<li class="like-vk"><input type="checkbox" id="like-vk" /><label for="like-vk">' + top.CKLang
				.LJLike_button_vkontakte + '</label></li>' : ''
		},
		{
			label: top.CKLang.LJLike_button_give,
			id: 'livejournal',
			abbr: 'lj',
			html: '<span class="lj-like-item lj-like-gag lj">' + top.CKLang.LJLike_button_give + '</span>',
			htmlOpt: '<li class="like-lj"><input type="checkbox" id="like-lj" /><label for="like-lj">' + top.CKLang
				.LJLike_button_give + '</label></li>'
		}
	];

	var note;

	var ljNoteData = {
		LJPollLink: {
			html: encodeURIComponent(top.CKLang.Poll_PollWizardNotice + '<br /><a href="#" lj-cmd="LJPollLink">' + top.CKLang
				.Poll_PollWizardNoticeLink + '</a>')
		},
		LJLike: {
			html: encodeURIComponent(top.CKLang.LJLike_WizardNotice + '<br /><a href="#" lj-cmd="LJLike">' + top.CKLang
				.LJLike_WizardNoticeLink + '</a>')
		},
		LJUserLink: {
			html: encodeURIComponent(top.CKLang.LJUser_WizardNotice + '<br /><a href="#" lj-cmd="LJUserLink">' + top.CKLang
				.LJUser_WizardNoticeLink + '</a>')
		},
		LJLink: {
			html: encodeURIComponent(top.CKLang.LJLink_WizardNotice + '<br /><a href="#" lj-cmd="LJLink">' + top.CKLang
				.LJLink_WizardNoticeLink + '</a>')
		},
		LJImage: {
			html: encodeURIComponent(top.CKLang.LJImage_WizardNotice + '<br /><a href="#" lj-cmd="LJImage">' + top.CKLang
				.LJImage_WizardNoticeLink + '</a>')
		},
		LJCut :{
			html: encodeURIComponent(top.CKLang.LJCut_WizardNotice + '<br /><a href="#" lj-cmd="LJCut">' + top.CKLang
				.LJCut_WizardNoticeLink + '</a>')
		}
	};

	var ljUsers = {};
	var currentNoteNode;

	function createNote(editor) {
		var timer,
			state,
			currentData,
			tempData,
			note,
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
					noteNode.style
						.filter = (currentStep >= 1) ? null : 'progid:DXImageTransform.Microsoft.Alpha(opacity=' + (currentStep * 100) + ')';
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
			if (!currentData.cmd) {
				note.hide();
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
				currentNoteNode = ljNoteData[cmd].node = currentData[cmd].node;
				editor.execCommand(cmd);
				note.hide(true);
			}
			return false;
		}

		function applyNote() {
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
					if (ljNoteData.hasOwnProperty(link.getAttribute('lj-cmd'))) {
						link.onclick = callCmd;
					}
				}
			} else {
				currentData = currentNoteNode = null;
			}

			animate(state);

			timer = null;
		}

		note = {
			show: function(data, isNow) {
				if (!isNow && data == tempData) {
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

		return note;
	}

	CKEDITOR.plugins.add('livejournal', {
		init: function(editor) {

			function findLJTags(evt) {
				var noteData,
					isSelection = evt.name == 'selectionChange',
					node = isSelection ? evt.data.element : evt.data.getTarget();

				if (node.type != 1) {
					node = node.getParent();
				}

				while (node) {
					if (!attr && node.type == 1) {
						if (node.is('img') && node.getParent().getParent() && node.getParent().getParent().getAttribute('contentEditable') != 'false') {
							node.setAttribute('lj-cmd', 'LJImage');
						} else if (node.is('a') && node.getParent().getAttribute('contentEditable') != 'false') {
							node.setAttribute('lj-cmd', 'LJLink');
						}
					}

					var attr = node.getAttribute('lj-cmd');

					if (attr && ljNoteData.hasOwnProperty(attr)) {
						if (isSelection) {
							ljNoteData[attr].node = node;
							editor.getCommand(attr).setState(CKEDITOR.TRISTATE_ON);
						}
						(noteData || (noteData = {}))[attr] = {
							content: ljNoteData[attr].html,
							node: node
						};
					}

					node = node.getParent();
				}

				noteData ? note.show(noteData) : note.hide();

				for (var command in ljNoteData) {
					if (ljNoteData.hasOwnProperty(command) && isSelection && (!noteData || !noteData.hasOwnProperty(command))) {
						delete ljNoteData[command].node;
						editor.getCommand(command).setState(CKEDITOR.TRISTATE_OFF);
					}
				}
			}
			
			editor.dataProcessor.toHtml = function(html, fixForBody) {
				html = html
					.replace(/(<lj [^>]+)(?!\/)>/gi, '$1 />')
					.replace(/(<lj-template[^>]*)(?!\/)>/gi, '$1 />')
					.replace(/<((?!br)[^\s>]+)([^>]*?)\/>/gi, '<$1$2></$1>')
					.replace(/<lj-poll .*?>[\s\S]*?<\/lj-poll>/gi, function(ljtags) {
						return new Poll(ljtags).outputHTML();
					});

				if (!$('event_format').checked) {
					html = html
						.replace(/(<lj-raw.*?>)([\s\S]*?)(<\/lj-raw>)/gi, function(result, open, content, close) {
							return open + content.replace(/\n/g, '') + close;
						})
						.replace(/\n/g, '<br />');
				}

				html = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, html, fixForBody);

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

			function checkLastLine(evt) {
				if(evt && evt.name == 'click'){
					evt.data.preventDefault();
					evt.data.stopPropagation();
				}
				var body = editor.document.getBody();
				var last = body.$.lastChild;
				if (last && last.nodeType == 1 && last.nodeName.toLowerCase() != 'br') {
					body.appendHtml('<br />');
				}
			}

			editor.on('selectionChange', findLJTags);
			editor.on('doubleclick', function(evt) {
				var node = evt.data.element;

				if (node.type != 1) {
					node = node.getParent();
				}

				while (node) {
					var cmd = node.getAttribute('lj-cmd');
					if (ljNoteData.hasOwnProperty(cmd)) {
						cmd = editor.getCommand(cmd);
						if (cmd.state == CKEDITOR.TRISTATE_ON) {
							editor.getSelection().selectElement(node);
							evt.data.dialog = '';
							cmd.exec();
							break;
						}
					}
					node = node.getParent();
				}
			});

			editor.on('dataReady', function() {
				note = note || createNote(editor);

				checkLastLine();
				editor.document.on('mouseout', note.hide);
				editor.document.on('mouseover', findLJTags);
				editor.document.on('keyup', checkLastLine);
				editor.document.on('click', checkLastLine);
				editor.document.on('selectionChange', checkLastLine);
				editor.document.on('afterCommandExec', checkLastLine);
			});

			//////////  LJ User Button //////////////
			var url = top.Site.siteroot + '/tools/endpoints/ljuser.bml';

			editor.addCommand('LJUserLink', {
				exec: function(editor) {
					var userName = '',
						selection = editor.getSelection(),
						LJUser = ljNoteData.LJUserLink.node;

					if (LJUser) {
						note.hide(true);
						userName = prompt(top.CKLang.UserPrompt, ljNoteData.LJUserLink.node.getElementsByTag('b').getItem(0)
							.getText());
					} else if (selection.getType() == 2) {
						userName = selection.getSelectedText();
					}

					if (userName == '') {
						userName = prompt(top.CKLang.UserPrompt, userName);
					}

					if (!userName) {
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
							tmpNode.setAttribute('contentEditable', 'false');
							tmpNode.setAttribute('lj-cmd', 'LJUserLink');

							if (LJUser) {
								LJUser.$.parentNode.replaceChild(tmpNode, LJUser.$);
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
			editor.addCommand('LJImage', {
				exec: function(editor) {
					var state = editor.getCommand('LJImage').state;

					if (ljNoteData.LJImage.node) {
						editor.getSelection().selectElement(ljNoteData.LJImage.node);
						editor.openDialog('image');
					} else if (state === CKEDITOR.TRISTATE_OFF) {
						if (window.ljphotoEnabled) {
							jQuery('#updateForm').photouploader({
								type: 'upload'
							}).photouploader('show').bind('htmlready', function (event, html) {
								editor.insertElement(new CKEDITOR.dom.element.createFromHtml(html, editor.document));
							});
						} else {
							editor.openDialog('image');
						}
					} else if (state === CKEDITOR.TRISTATE_ON) {
						editor.openDialog('image');
					}
					note.hide(true);
				},
				editorFocus: false
			});

			editor.ui.addButton('LJImage', {
				label: editor.lang.common.imageButton,
				command: 'LJImage'
			});

			//////////  LJ Link Button //////////////
			editor.addCommand('LJLink', {
				exec: function(editor) {
					var state = editor.getCommand('LJLink').state;

					if (currentNoteNode && ljNoteData.LJLink.node) {
						editor.getSelection().selectElement(ljNoteData.LJLink.node);
						editor.openDialog('link');
					} else if (state === CKEDITOR.TRISTATE_OFF) {
						editor.openDialog('link');
					} else if (state === CKEDITOR.TRISTATE_ON) {
						editor.execCommand('unlink')
					}
					note.hide(true);

				},
				editorFocus: false
			});

			editor.ui.addButton('LJLink', {
				label: editor.lang.link.toolbar,
				command: 'LJLink'
			});

			//////////  LJ Justify //////////////
			(function() {
				function getState(editor, path) {
					var firstBlock = path.block || path.blockLimit;

					if (!firstBlock || firstBlock.getName() == 'body') {
						return CKEDITOR.TRISTATE_OFF;
					}

					return ( getAlignment(firstBlock, editor.config.useComputedState) == this.value ) ? CKEDITOR
						.TRISTATE_ON : CKEDITOR.TRISTATE_OFF;
				}

				function getAlignment(element, useComputedState) {
					useComputedState = useComputedState === undefined || useComputedState;

					var align;
					if (useComputedState) {
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

					var command = evt.editor.getCommand(this.name);
					command.state = getState.call(this, evt.editor, evt.data.path);
					command.fire('state');
				}

				function JustifyCommand(editor, name, value) {
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

				JustifyCommand.prototype = {
					exec : function(editor) {
						var LJNode = ljNoteData.LJLike.node || ljNoteData.LJUserLink.node;
						if (LJNode) {
							LJNode.removeAttribute('contenteditable');
							editor.getSelection().selectElement(LJNode);
						}

						var selection = editor.getSelection(),
							enterMode = editor.config.enterMode;

						if (!selection) {
							return;
						}

						var bookmarks = selection.createBookmarks(),
							ranges = selection.getRanges(true);

						var cssClassName = this.cssClassName,
							iterator,
							block;

						var useComputedState = editor.config.useComputedState;
						useComputedState = useComputedState === undefined || useComputedState;

						for (var i = ranges.length - 1; i >= 0; i--) {
							iterator = ranges[ i ].createIterator();
							iterator.enlargeBr = enterMode != CKEDITOR.ENTER_BR;

							while (( block = iterator.getNextParagraph(enterMode == CKEDITOR.ENTER_P ? 'p' : 'div') )) {
								block.removeAttribute('align');
								block.removeStyle('text-align');

								// Remove any of the alignment classes from the className.
								var className = cssClassName && ( block.$.className = CKEDITOR.tools.ltrim(block.$.className
									.replace(this.cssClassRegex, '')) );

								var apply = ( this.state == CKEDITOR
									.TRISTATE_OFF ) && ( !useComputedState || ( getAlignment(block, true) != this.value ) );

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

						editor.focus();
						editor.forceNextSelectionCheck();
						selection.selectBookmarks(bookmarks);

						if (LJNode) {
							LJNode.setAttribute('contenteditable', 'false');
						}
					}
				};

				var left = new JustifyCommand(editor, 'justifyleft', 'left'),
					center = new JustifyCommand(editor, 'justifycenter', 'center'),
					right = new JustifyCommand(editor, 'justifyright', 'right');

				editor.addCommand('justifyleft', left);
				editor.addCommand('justifycenter', center);
				editor.addCommand('justifyright', right);

				editor.ui.addButton('JustifyLeft', {
					label : editor.lang.justify.left,
					command : 'justifyleft'
				});
				editor.ui.addButton('JustifyCenter', {
					label : editor.lang.justify.center,
					command : 'justifycenter'
				});
				editor.ui.addButton('JustifyRight', {
					label : editor.lang.justify.right,
					command : 'justifyright'
				});

				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, left));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, right));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, center));
				editor.on('dirChanged', onDirChanged);

			})();

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

			editor.addCss('.lj-embed' + '{' + 'background-image: url(' + CKEDITOR.getUrl(this
				.path + 'images/placeholder_flash.png') + ');' + 'background-position: center center;' + 'background-repeat: no-repeat;' + 'background-color: #CCCCCC;' + 'border: 1px dotted #000000;' + 'min-height: 80px;' + '}');

			function doEmbed(content) {
				if (content && content.length) {
					if (window.switchedRteOn) {
						editor.insertElement(new CKEDITOR.dom.element.createFromHtml('<div class="lj-embed" contentEditable="false">' + content + '</div><br/>', editor.document));
					}
				}
			}

			//////////  LJ Cut Button //////////////
			editor.addCommand('LJCut', {
				exec: function() {
					var text;
					if (ljNoteData.LJCut.node) {
						text = prompt(top.CKLang.CutPrompt, ljNoteData.LJCut.node.getAttribute('text') || top.CKLang.ReadMore);
						if (text) {
							if (text == top.CKLang.ReadMore) {
								ljNoteData.LJCut.node.removeAttribute('text');
							} else {
								ljNoteData.LJCut.node.setAttribute('text', text);
							}
						}
					} else {
						text = prompt(top.CKLang.CutPrompt, top.CKLang.ReadMore);
						if (text) {
							var selection = editor.document.getSelection();

							ljNoteData.LJCut.node = new CKEDITOR.dom.element('lj:cut', editor.document);
							ljNoteData.LJCut.node.setAttribute('lj-cmd', 'LJCut');
							if (text != top.CKLang.ReadMore) {
								ljNoteData.LJCut.node.setAttribute('text', text);
							}

							var ranges = selection.getRanges();
							selection.lock();
							for (var i = 0, l = ranges.length; i < l; i++) {
								var range = ranges[i];
								range.extractContents().appendTo(ljNoteData.LJCut.node);
							}
							selection.unlock();
							editor.insertElement(ljNoteData.LJCut.node);
							selection.selectElement(ljNoteData.LJCut.node);
						}
						note.hide(true);
					}
				}
			});

			editor.ui.addButton('LJCut', {
				label: top.CKLang.LJCut,
				command: 'LJCut'
			});

			//////////  LJ Poll Button //////////////
			if (top.canmakepoll) {
				var currentPoll;

				CKEDITOR.dialog.add('LJPollDialog', function() {
					var isAllFrameLoad = 0, okButtonNode, questionsWindow, setupWindow;

					var onLoadPollPage = function() {
						if (this.removeListener) {
							this.removeListener('load', onLoadPollPage);
						}
						if (isAllFrameLoad && okButtonNode) {
							currentPoll = new Poll(ljNoteData.LJPollLink.node && unescape(ljNoteData.LJPollLink.node
								.getAttribute('data')), questionsWindow.document, setupWindow.document, questionsWindow.Questions);

							questionsWindow.ready(currentPoll);
							setupWindow.ready(currentPoll);

							okButtonNode.style.display = 'block';
						} else {
							isAllFrameLoad++;
						}
					};

					var buttonsDefinition = [new CKEDITOR.ui.button({
						type: 'button',
						id: 'LJPool_Ok',
						label: editor.lang.common.ok,
						onClick: function(evt) {
							evt.data.dialog.hide();
							var pollSource = new Poll(currentPoll, questionsWindow.document, setupWindow.document, questionsWindow
								.Questions).outputHTML();

							if (pollSource.length > 0) {
								if (ljNoteData.LJPollLink.node) {
									var node = editor.document.createElement('div');
									node.$.innerHTML = pollSource;
									ljNoteData.LJPollLink.node.insertBeforeMe(node);
									ljNoteData.LJPollLink.node.remove();
								} else {
									editor.insertElement(new CKEDITOR.dom.element.createFromHtml(pollSource, editor.document));
								}
								ljNoteData.LJPollLink.node = null;
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
							note.hide(true);
							if (isAllFrameLoad) {
								currentPoll = new Poll(ljNoteData.LJPollLink.node && unescape(ljNoteData.LJPollLink.node
									.getAttribute('data')), questionsWindow.document, setupWindow.document, questionsWindow.Questions);

								questionsWindow.ready(currentPoll);
								setupWindow.ready(currentPoll);
							}
						},
						contents: [
							{
								id: 'LJPool_Setup',
								label: 'Setup',
								padding: 0,
								elements: [
									{
										type: 'html',
										html: '<iframe src="/tools/ck_poll_setup.bml" allowTransparency="true" frameborder="0" style="width:100%; height:320px;"></iframe>',
										onShow: function(data) {
											if (!okButtonNode) {
												(okButtonNode = document.getElementById(data.sender.getButton('LJPool_Ok').domId).parentNode)
													.style.display = 'none';
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
								id: 'LJPool_Questions',
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
						note.show(top.CKLang.Poll_AccountLevelNotice, null, null, true);
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
					ljLikeDialog.getButton('LJLike_Ok')
						.getElement()[countChanges == 0 ? 'addClass' : 'removeClass']('btn-disabled');
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
							likeHtml = '',
							likeNode = ljNoteData.LJLike.node;

						for (var i = 0; i < buttonsLength; i++) {
							var button = likeButtons[i];
							var input = document.getElementById('like-' + button.abbr);
							var currentBtn = likeNode && likeNode.getAttribute('buttons');
							if ((input && input.checked) || (currentBtn && !button.htmlOpt && (currentBtn.indexOf(button
								.abbr) + 1 || currentBtn.indexOf(button.id) + 1))) {
								attr.push(button.id);
								likeHtml += button.html;
							}
						}

						if (attr.length) {
							if (likeNode) {
								ljNoteData.LJLike.node.setAttribute('buttons', attr.join(','));
								ljNoteData.LJLike.node.setHtml(likeHtml);
							} else {
								editor.insertElement(new CKEDITOR.dom.element
									.createFromHtml('<div contentEditable="false" class="lj-like" lj-cmd="LJLike" buttons="' + attr
									.join(',') + '">' + likeHtml + '</div><br/>', editor.document));
							}
						} else if (likeNode) {
							ljNoteData.LJLike.node.remove();
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
						note.hide(true);
						var command = editor.getCommand('LJLike');
						var i = countChanges = 0,
							isOn = command.state == CKEDITOR.TRISTATE_ON,
							buttons = ljNoteData.LJLike.node && ljNoteData.LJLike.node.getAttribute('buttons');

						for (; i < buttonsLength; i++) {
							var isChecked = buttons ? !!(buttons.indexOf(likeButtons[i].abbr) + 1 || buttons.indexOf(likeButtons[i]
								.id) + 1) : true;

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
		},
		afterInit: function(editor) {
			var dataProcessor = editor.dataProcessor;

			dataProcessor.dataFilter.addRules({
				elements: {
					'lj-embed': function(element) {
						var fakeElement = new CKEDITOR.htmlParser.element('div');
						fakeElement.attributes.contentEditable = 'false';
						fakeElement.attributes['class'] = 'lj-embed';
						fakeElement.attributes.embedid = element.attributes.id;
						if (element.attributes.hasOwnProperty('source_user')) {
							fakeElement.attributes.source_user = element.attributes.source_user;
						}
						fakeElement.children = element.children;

						return fakeElement;
					},
					'lj-like': function(element) {
						var attr = [];

						var fakeElement = new CKEDITOR.htmlParser.element('div');
						fakeElement.attributes.contentEditable = 'false';
						fakeElement.attributes['class'] = 'lj-like';
						fakeElement.attributes['lj-cmd'] = 'LJLike';

						var currentButtons = element.attributes.buttons && element.attributes.buttons.split(',') || likeButtons
							.defaultButtons;

						var length = currentButtons.length;
						for (var i = 0; i < length; i++) {
							var buttonName = currentButtons[i].replace(/^\s*([a-z]{2,})\s*$/i, '$1');
							var button = likeButtons[buttonName];
							if (button) {
								var buttonNode = new CKEDITOR.htmlParser.fragment.fromHtml(button.html).children[0];
								fakeElement.add(buttonNode);
								attr.push(buttonName);
							}
						}

						fakeElement.attributes.buttons = attr.join(',');
						fakeElement.attributes.style = element.attributes.style;
						return fakeElement;
					},
					'lj': function(element) {
						var ljUserName = element.attributes.user;
						if (!ljUserName || !ljUserName.length) {
							return;
						}

						var ljUserTitle = element.attributes.title;
						var cacheName = ljUserTitle ? ljUserName + ':' + ljUserTitle : ljUserName;

						if (ljUsers.hasOwnProperty(cacheName)) {
							var ljTag = (new CKEDITOR.htmlParser.fragment.fromHtml(ljUsers[cacheName])).children[0];

							ljTag.attributes['lj-cmd'] = 'LJUserLink';
							ljTag.attributes.contentEditable = 'false';
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

									var ljTags = editor.document.getElementsByTag('lj');

									for (var i = 0, l = ljTags.count(); i < l; i++) {
										var ljTag = ljTags.getItem(i);

										var userName = ljTag.getAttribute('user');
										var userTitle = ljTag.getAttribute('title');
										if (cacheName == (userTitle ? userName + ':' + userTitle : userName)) {
											var newLjTag = new CKEDITOR.dom.element.createFromHtml(ljUsers[cacheName], editor.document);
											newLjTag.setAttribute('lj-cmd', 'LJUserLink');
											newLjTag.setAttribute('contentEditable', 'false');
											ljTag.insertBeforeMe(newLjTag);
											ljTag.remove();
										}
									}
								}
							});
						}
					},
					'lj-map': function(element) {
						return new CKEDITOR.htmlParser.fragment.fromHtml('' + '<div style="' + 'width: ' + (isNaN(element.attributes
							.width) ? 100 : element.attributes.width) + 'px;' + 'height: ' + (isNaN(element.attributes
							.height) ? 100 : element.attributes
							.height) + 'px;"' + 'contentEditable="false"' + 'lj-url="' + (encodeURIComponent(element.attributes
							.url) || '') + '"' + 'class="lj-map"><p>map</p>' + '</div>').children[0];
					},
					'lj-repost': function(element) {
						var fakeElement = new CKEDITOR.htmlParser.element('input');
						fakeElement.attributes.type = 'button';
						fakeElement.attributes.value = (element.attributes && element.attributes.button.length && element.attributes.button) || top.CKLang.LJRepost_Value;
						fakeElement.attributes['class'] = 'lj-repost';
						return fakeElement;
					},
					'lj-cut': function(element) {
						element.name = 'lj:cut';
						element.attributes['lj-cmd'] = 'LJCut';
					},
					'lj-raw': function(element) {
						element.name = 'lj:raw';
					},
					'lj-wishlist': function(element) {
						element.name = 'lj:wishlist';
					},
					'lj-template': function(element){
						element.name = 'lj:template';
						element.attributes.contentEditable = 'false';
						element.children.length = 0;
					},
					a: function(element) {
						if(element.parent.attributes && element.parent.attributes.contentEditable != 'false'){
							element.attributes['lj-cmd'] = 'LJLink';
						}
					},
					img: function(element) {
						var parent = element.parent.parent;
						if (!parent || !parent.attributes || parent.attributes.contentEditable != 'false') {
							element.attributes['lj-cmd'] = 'LJImage';
						}
					},
					div: function(element){
						if(element.attributes && element.attributes['class'] == 'ljcut'){
							var newElement = new CKEDITOR.htmlParser.element('lj:cut');
							newElement.attributes['lj-cmd'] = 'LJCut';
							newElement.children = element.children;
							return newElement;
						}
					}
				}
			}, 5);

			dataProcessor.htmlFilter.addRules({
				elements: {
					div: function(element) {
						var newElement = element;
						switch (element.attributes['class']) {
							case 'lj-like':
								newElement = new CKEDITOR.htmlParser.element('lj-like');
								newElement.attributes.buttons = element.attributes.buttons;
								if (element.attributes.style) {
									newElement.attributes.style = element.attributes.style;
								}
								newElement.isEmpty = true;
								newElement.isOptionalClose = true;
								break;
							case 'lj-embed':
								newElement = new CKEDITOR.htmlParser.element('lj-embed');
								newElement.attributes.id = element.attributes.embedid;
								if (element.attributes.hasOwnProperty('source_user')) {
									newElement.attributes.source_user = element.attributes.source_user;
								}
								newElement.children = element.children;
								newElement.isOptionalClose = true;
								break;
							case 'lj-map':
								newElement = new CKEDITOR.htmlParser.element('lj-map');
								newElement.attributes.url = decodeURIComponent(element.attributes['lj-url']);
								element.attributes.style && element.attributes.style.replace(/([a-z-]+):(.*?);/gi, function(relust, name, value) {
									newElement.attributes[name] = parseInt(value);
								});

								newElement.isOptionalClose = newElement.isEmpty = true;
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
							var userTitle = element.children[1].children[0].children[0].value;

							if (userTitle && userTitle != userName) {
								ljUserNode.attributes.title = userTitle;
							}

							ljUserNode.isOptionalClose = ljUserNode.isEmpty = true;
							return ljUserNode;
						} else if(element.attributes.style == 'display: none;'){
							return false;
						}
					},
					input: function(element) {
						if (element.attributes['class'] == 'lj-repost') {
							var newElement = new CKEDITOR.htmlParser.element('lj-repost');
							if(element.attributes.value != top.CKLang.LJRepost_Value){
								newElement.attributes.button = element.attributes.value;
							}
							newElement.isOptionalClose = newElement.isEmpty = true;
							return newElement;
						}
					},
					form: function(element) {
						if (element.attributes['class'] == 'ljpoll') {
							return new CKEDITOR.htmlParser.fragment.fromHtml(unescape(element.attributes.data)).children[0];
						}
					},
					'lj:template': function(element){
						element.name = 'lj-template';
						element.isOptionalClose = element.isEmpty = true;
					},
					'lj:cut': function(element){
						element.name = 'lj-cut'
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
