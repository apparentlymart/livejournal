(function() {
	'use strict';

	/*
	 * CKEDITOR.prototype.setData light version
	 * doesnt recreate whole iframe each time
	 * @param {String} data Editor content
	 */
	CKEDITOR.editor.prototype.lightSetData = function(data) {
		this.document.getBody().setHtml(this.dataProcessor.toHtml(data));
		this.fire('contentDom');
	};


	/*
	 * Update 'editor.editdataWithFocus' with
	 * data + focus (as span element with id '__rte_focus')
	 *
	 * Used for focus transtition between rte and html modes
	 * (only when range is collapsed)
	 */
	CKEDITOR.editor.prototype.insertCaret = function() {
		this.focus();

		var selection = this.getSelection(),
			range = selection && selection.getRanges()[0];

		if (!range || !range.collapsed) {
			return false;
		}

		var span = new CKEDITOR.dom.element('span');
		span.setAttribute('id', '__rte_focus');
		span.setText('|');

		range.insertNode(span);

		this.dataWithFocus = this.getData();

		span.remove();
	};


	/*
	 * Move focus to either start or end of editor content
	 * @param {String} where Could be 'start' or 'end'
	 */
	CKEDITOR.editor.prototype.moveFocus = function(where) {
		var self = this;
		this.focus();

		setTimeout(function() {
			var s = self.getSelection(),
				selected_ranges = s && s.getRanges(),
				node = selected_ranges && selected_ranges[0].startContainer,
				parents = node && node.getParents(true);

			if (!node) {
				return;
			}

			if (where === 'end') {
		        node = parents[parents.length - 2].getFirst();
		        if (!node) {
					return;
		        }

		        while (true) {
		            var x = node.getNext();
		            if (x == null) {
		                break;
		            }
		            node = x;
		        }

		        s.selectElement(node);
		        selected_ranges = s.getRanges();
		        selected_ranges[0].collapse(false);
		        s.selectRanges(selected_ranges);
			}

			if (where === 'start') {

					var range = new CKEDITOR.dom.range( self.document );
					range.selectNodeContents( self.document.getBody() );
					range.collapse(true);
					s.selectRanges([ range ]);

			}
		}, 100); // need some time for selection
	};


	/*
	 * Check if editor's focus at the specified position
	 * @param {String} where Could be 'start' or 'end'
	 */
	CKEDITOR.editor.prototype.isFocusAt = function(where) {
		var selection = this.getSelection(),
			range = selection.getRanges()[0],
			body = this.document.getBody();

		if (where === 'end' && range.checkEndOfBlock()) {
			if (body.equals(range.endContainer) || body.getLast().equals(range.endContainer)) {
				return true;
			}
		}

		if (where === 'start') {
			throw new Error('Not implemented');
		}

		return false;
	};


	/*
	 * Check if selection is collapsed
	 * @return {Boolean}
	 */
	CKEDITOR.editor.prototype.isSelectionCollapsed = function() {
		var selection = this.getSelection(),
			range = selection && selection.getRanges()[0];

		if (range) {
			return !!range.collapsed;
		}

		return false;
	};

	var CKLang = CKEDITOR.lang[CKEDITOR.lang.detect()] || {};
	jQuery.extend(CKLang, LJ.pageVar('rtedata'));
	window.CKLang = CKEDITOR.CKLang = CKLang;

	if (Site.page.ljpost) {
		CKEDITOR.styleText = Site.statprefix + '/js/ck/contents_new.css?t=' + Site.version;
	} else {
		CKEDITOR.styleText = Site.statprefix + '/js/ck/contents.css?t=' + Site.version;
	}

	var focusToken = '@focus@',
		focusTransformed = '<input type="hidden" id="__focus"/>';

	function rteButton(button, widget, options) {
		options = options || {};

		options && jQuery.extend(options, {
			fromDoubleClick: this.execFromEditor
		});

		LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), options);

		this.execFromEditor = false;
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
			label: CKLang.LJLike_button_surfingbird,
			id: 'surfingbird',
			abbr: 'sb',
			checked: Site.remote_is_sup ? true : false,
			html: '<span class="lj-like-item sb">' + CKLang.LJLike_button_surfingbird + '</span>',
			htmlOpt: Site.remote_is_sup? '<li class="like-sb"><input type="checkbox" id="like-sb" /><label for="like-sb">' + CKLang.LJLike_button_surfingbird + '</label></li>' : ''
		},
		{
			label: CKLang.LJLike_button_tumblr,
			id: 'tumblr',
			abbr: 'tb',
			checked: true,
			html: '<span class="lj-like-item tb">' + CKLang.LJLike_button_tumblr + '</span>',
			htmlOpt: '<li class="like-tb"><input type="checkbox" id="like-tb" /><label for="like-tb">' + CKLang.LJLike_button_tumblr + '</label></li>'
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
		},/*
		LJUserLink: {
			html: encodeURIComponent(CKLang.LJUser_WizardNotice + '<br /><a href="#" lj-cmd="LJUserLink">' + CKLang.LJUser_WizardNoticeLink + '</a>')
		},*/
		LJLink2: {
			html: encodeURIComponent(CKLang.LJLink_WizardNotice + '<br /><a href="#" lj-cmd="LJLink2">' + CKLang.LJLink_WizardNoticeLink + '</a>')
		},
		LJImage: {
			html: encodeURIComponent(CKLang.LJImage_WizardNotice + '<br /><a href="#" lj-cmd="LJImage">' + CKLang.LJImage_WizardNoticeLink + '</a>')
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
	dtd.$empty['lj-random'] = 1;

	dtd['lj-template'] = {};
	dtd['lj-map'] = {};
	dtd['lj-repost'] = {};
	dtd['lj-raw'] = dtd.div;

	// set allowed tags for poll, for reference check
	// http://docs.cksource.com/ckeditor_api/symbols/CKEDITOR.dtd.html

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

	['a', 'b', 'em', 'i', 'img', 'strong', 'u', 'lj-user'].forEach(function(tag) {
		dtd['lj-pq'][tag] = 1;
		dtd['lj-pi'][tag] = 1;
	});

	dtd.$block.iframe = dtd.$inline.iframe;
	delete dtd.$inline.iframe;

	CKEDITOR.tools.extend(dtd['lj-cut'] = {}, dtd.$block);
	CKEDITOR.tools.extend(dtd['lj-spoiler'] = {}, dtd.$block);

	CKEDITOR.tools.extend(dtd['lj-cut'], dtd.$inline);
	CKEDITOR.tools.extend(dtd['lj-spoiler'], dtd.$inline);

	CKEDITOR.tools.extend(dtd.div, dtd.$block);
	CKEDITOR.tools.extend(dtd.$body, dtd.$block);

	delete dtd['lj-cut']['lj-cut'];

	// CKEDITOR.dtd.$empty['lj-embed'] = 1;

	// <lj user...> transforms to iframe https://jira.sup.com/browse/LJSUP-13877
	CKEDITOR.dtd.p.iframe = 1;

	// https://jira.sup.com/browse/LJSV-2404
	CKEDITOR.dtd['lj-cut']['iframe'] = 1;
	CKEDITOR.dtd['lj-spoiler']['iframe'] = 1;

	CKEDITOR.plugins.add('livejournal', {
		init: function(editor) {
			editor.rteButton = rteButton;

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
							editor.execFromEditor = true;
							// cmd.exec();

							editor.execCommand(cmdName, true);

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
					editor.focus();
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

				if (iframeBody.on && !Site.page.disabled_input) {
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
				var frames = editor.document.getElementsByTag('iframe'),
					length = frames.count(), frame,
					cmd, frameWin, doc, ljStyle;

				editor.execFromEditor = false;

				while (length--) {
					frame = frames.getItem(length),
					cmd = frame.getAttribute('lj-cmd'),
					frameWin = frame.$.contentWindow,
					doc = frameWin.document,
					ljStyle = frame.getAttribute('lj-style') || '';

					if (frame.getAttribute('data-update') === 'false') {
						continue;
					}

					if (doc && doc.body && doc.body.getAttribute('data-loaded')) {
						continue;
					}

					frame.removeListener('load', onLoadFrame);
					frame.on('load', onLoadFrame);
					doc.open();
					doc.write('<!DOCTYPE html>' +
						'<html style="' + ljStyle + '">' +
							'<head><link rel="stylesheet" href="' + CKEDITOR.styleText + '" /></head>' +
							'<body data-loaded="true" scroll="no" class="' + (frame.getAttribute('lj-class') || '') + '" style="' + ljStyle + '" ' + (cmd ? ('lj-cmd="' + cmd + '"') : '') + '>'
								+ decodeURIComponent(frame.getAttribute('lj-content') || '') +
							'</body>' +
						'</html>');
					doc.close();
				}
			}
			editor.updateFrames = updateFrames;

			/*
			 * only Firefox needs this (frames are not updated when
			 * switching from HTML to visual editor) for the first time
			 */
			editor.on('dataReady', function() {
				setTimeout(updateFrames, 100);
			});

			function findLJTags(evt) {
				editor.fire('updateSnapshot');
				if (editor.onSwitch === true) {
					delete editor.onSwitch;
					return;
				}

				var noteData, isClick = evt.name == 'click', isSelection = evt.name == 'selectionChange' || isClick, target = evt.data.element || evt.data.getTarget(), node, command;

				if (isClick && (evt.data.getKey() === 1 || evt.data.$.button === 0)) {
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
						if (node.is('img') && !node.hasAttribute('data-user') && parent.getParent() && !parent.getParent().hasAttribute('data-user')) {
							attr = 'LJImage';
							node.setAttribute('lj-cmd', attr);
						} else if (node.is('a') && !node.hasAttribute('data-user') && !parent.hasAttribute('lj:user')) {
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

				var editorCommand;
				if (isSelection) {
					for (command in ljTagsData) {
						if (ljTagsData.hasOwnProperty(command) && (!noteData || !noteData.hasOwnProperty(command))) {
							delete ljTagsData[command].node;
							editorCommand = editor.getCommand(command);
							if (editorCommand) {
								editorCommand.setState(CKEDITOR.TRISTATE_OFF);
							}
						}
					}
				}
				editor.fire('updateSnapshot');
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

				/*
				 * Find and move token out from markup
				 */
				function moveToken(s, token) {
				    return s.replace(/<(.|\n)*?>/g, function(match) {
				        var z = match;

				        if (z.indexOf(token) !== -1) {
				            z = z.replace(token, '');
				            return z + token;
				        } else {
				            return match;
				        }
				    });
				}

				/*
				 * Insert token at position in string
				 */
				function insertAt(s, position, token) {
					return [s.slice(0, position), token, s.slice(position)].join('');
				}

				/*
				 * Transform html focus to rte focus
				 */
				editor.on('contentDom', function(event) {
					var htmlFocus = event.editor.document.getById('__focus');

					if (htmlFocus) {
						this._domBuilt = true;

						setTimeout(function() {
							event.editor.focus();

							var selection = event.editor.getSelection();
							if (selection) {
								var range = new CKEDITOR.dom.range(event.editor.document);
								range.setEndAfter(htmlFocus);
								selection.selectRanges([range]);
							}
							htmlFocus.remove();

							editor.fire('updateSnapshot');
						}, this._domBuilt ? 0 : 100);
					}
				});

				editor.dataProcessor.toHtml = function(html, fixForBody) {

					// focus transformations
					var position = Site.page.__htmlLast;
					if (typeof position === 'number') {
						if (html.length > 0) {
							html = moveToken(
								insertAt(html, position, focusToken),
								focusToken
							).replace(focusToken, focusTransformed);
						} else {
							html = focusTransformed;
						}
						delete Site.page.__htmlLast;
					}

					html = html.replace(/<lj [^>]*?>/gi, closeTag)
						.replace(/<lj-map [^>]*?>/gi, closeTag)
						.replace(/<lj-template[^>]*?>/gi, closeTag)
						.replace(/(<lj-cut[^>]*?)\/>/gi, '$1>')
						.replace(/<((?!br)[^\s>]+)([^>]*?)\/>/gi, '<$1$2></$1>')
						.replace(/<lj-poll.*?>[\s\S]*?<\/lj-poll>/gi, createPoll)
						.replace(/<lj-poll-([0-9]+)>/gi, createUneditablePoll)
						.replace(/<lj-repost\s*(?:button\s*=\s*(?:"([^"]*?)")|(?:"([^']*?)"))?.*?>([\s\S]*?)<\/lj-repost>/gi, createRepost)
						.replace(/<lj-embed(.*?)>([\s\S]*?)<\/lj-embed>/gi, createEmbed)
						.replace(/(<lj-raw.*?>)([\s\S]*?)(<\/lj-raw>)/gi, createLJRaw)
						.replace(/\n/g, '<br/>');

					// Fix tables: LJSUP-14409, LJSUP-13714
					html = html
						.replace(/>\s+<tr/ig, '><tr')
						.replace(/>\s+<\/tr/ig, '></tr')
						.replace(/>\s+<td/ig, '><td')
						.replace(/>\s+<\/td/ig, '></td')
						.replace(/<\/tr>\s+<\/table>/ig, '</tr></table>')
						.replace(/<tr>\n/ig, '<tr>')
						.replace(/\n<\/tr>/ig, '</tr>')
						.replace(/<td>\n/ig, '<td>')
						.replace(/\n<\/td>/ig, '</td>');


					html = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, html, fixForBody);

					if (CKEDITOR.env.ie) {
						html = '<xml:namespace ns="livejournal" prefix="lj" />' + html;
					}

					return html;
				};
			})();

			editor.dataProcessor.toDataFormat = function(html, fixForBody) {
				html = CKEDITOR.htmlDataProcessor.prototype.toDataFormat.call(this, html, fixForBody);
				html = html.replace(/<br\s*\/>/gi, '\n');
				return html.replace(/\t/g, ' ');
			};

			editor.dataProcessor.writer.indentationChars = '';
			editor.dataProcessor.writer.lineBreakChars = '';

			editor.on('selectionChange', findLJTags);
			editor.on('doubleclick', onDoubleClick);
			editor.on('afterCommandExec', updateFrames);
			editor.on('dialogHide', updateFrames);

			/*
			 * Fix paste by removing last line break,
			 * which occurs every time (LJSUP-14448).
			 */
			(function() {
				var lastBr = /<br\s*\/?>$/i;
				editor.on('paste', function(e) {
					e.data.html = e.data.html.replace(lastBr, '');
				});
			})();


			editor.on('dataReady', function() {
				if (CKEDITOR.env.ie) {
					editor.document.getBody().on('dragend', updateFrames);
					editor.document.getBody().on('paste', function () {
						setTimeout(updateFrames, 0);
					});
				}

				if (!Site.page.disabled_input) {
					editor.document.on('click', findLJTags);
					editor.document.on('mouseover', findLJTags);
					editor.document.getBody().on('keyup', onKeyUp);
					updateFrames();
				}
			});

			// LJ Buttons

			// LJ Image
			(function() {
				var button = "LJImage", selectedImage = null;

				// registered in jquery/mixins/editpic.js
				LiveJournal.register_hook('editpic_response', function(data) {
					var selected = selectedImage,
						parent = selected && selected.getParent();

					if (!selected) {
						return;
					}

					if (data.url) {
						selected.setAttribute('src', data.url);
						selected.setAttribute('data-cke-saved-src', data.url);
					} else {
						if (parent && parent.getName() === 'a') {
							parent.remove();
						} else {
							selected.remove();
						}
						return;
					}

					if (data.width) {
						selected.setAttribute('width', data.width);
					} else {
						selected.removeAttribute('width');
					}

					//
					if (data.height) {
						selected.setAttribute('height', data.height);
					} else {
						selected.removeAttribute('height');
					}

					// title
					if (data.title) {
						selected.setAttribute('title', data.title);
					} else {
						selected.removeAttribute('title');
					}

					// image border
					if (data.border) {
						selected.setStyle('border-width', data.border + "px");
					} else {
						selected.removeStyle('border-width');
						selected.removeStyle('border-style');
					}

					// vertical space
					if (data.vspace) {
						selected.setStyles({
							'margin-top'   : data.vspace + 'px',
							'margin-bottom': data.vspace + 'px'
						});
					} else {
						selected.removeStyle('margin-top');
						selected.removeStyle('margin-bottom');
					}

					// horizontal space
					if (data.hspace) {
						selected.setStyles({
							'margin-left' : data.hspace + 'px',
							'margin-right': data.hspace + 'px'
						});
					} else {
						selected.removeStyle('margin-left');
						selected.removeStyle('margin-right');
					}

					// image link
					var parent = selected && selected.getParent();
					if (data.link) {
						data.link = data.link.replace(/^[\s\t]*(?:http:\/\/)?/, 'http://');
						// change parent link if exists
						if (parent && parent.getName() === 'a') {
							parent.setAttribute('href', data.link);
							parent.setAttribute('data-cke-saved-href', data.link);

							if (data.blank) {
								parent.setAttribute('target', '_blank');
							} else {
								parent.removeAttribute('target');
							}
						} else {
							// or create a new one
							var link = new CKEDITOR.dom.element('a', editor.document);
							link.setAttribute('href', data.link);
							if (data.blank) {
								link.setAttribute('target', '_blank');
							}

							selected.insertBeforeMe(link);
							link.append(selected);

							editor.getSelection() && editor.getSelection().selectElement(link);
						}
					} else {
						// on empty link remove parent 'a' and replace it with selected image
						if (parent.getName() === 'a') {
							parent.insertBeforeMe(selected);
							parent.remove();
						}
					}

					// image aligment
					if (data.aligment && data.aligment !== 'none') {
						selected.setStyle('float', data.aligment);
					} else {
						selected.removeStyle('float');
					}

					selectedImage = null;
				});

				editor.addCommand(button, {
					exec: function (editor, fromDoubleClick) {
						var selected = editor.getSelection();

						selected = selected? selected.getSelectedElement() : null;
						selectedImage = selected;

						if (selected && selected.is('img')) {
							var parent = selected && selected.getParent(),
								hasParentLink = parent.getName() === 'a',
								parentLink = hasParentLink && parent,
								parentHref = hasParentLink && parent.getAttribute('href'),
								natural = {};

							if ('naturalWidth' in selected.$) {
								natural.width = selected.$.naturalWidth;
								natural.height = selected.$.naturalHeight;
							} else {
								// IE 8 or lower
								var img = new Image();
								img.src = selected.$.src;

								natural = {
									width: img.width,
									height: img.height
								};
							}

							editor.rteButton(button, 'editpic', {
								picData: {
									url: selected.getAttribute('src'),
									title: selected.getAttribute('title'),

									width: selected.getAttribute('width') || selected.$.width,
									height: selected.getAttribute('height') || selected.$.height,

									defaultWidth: natural.width,
									defaultHeight: natural.height,

									link: parentHref || "",
									blank: (hasParentLink? !!parentLink.getAttribute('target') : true),

									border: parseInt(selected.getStyle('border-width'), 10),
									vspace: parseInt(selected.getStyle('margin-top'), 10),
									hspace: parseInt(selected.getStyle('margin-left'), 10),

									aligment: selected.getStyle('float') || 'none'
								}
							});
						} else {
							jQuery('.b-updatepage-event-section').editor('handleImageUpload', 'upload');
						}
					},
					editorFocus: false
				});

				editor.ui.addButton(button, {
					label: CKLang.LJImage_Title,
					command: button
				});
			})();

			// LJ Embed
			(function () {
				var lastSelectedIframe = null;

				editor.on('selectionChange', function(event) {
					var element = event.data.element;

					if (element.is('iframe')) {
						lastSelectedIframe = element;
					} else {
						lastSelectedIframe = null;
					}
				});

				var button = "LJEmbedLink",
					widget = 'video';

				function insertEmbed(content) {
					var iframe = new CKEDITOR.dom.element('iframe', editor.document);

					if (content !== LiveJournal.getEmbed(content)) {
						var node = CKEDITOR.dom.element.createFromHtml(LiveJournal.getEmbed(content));

						var background = "";
						var media = LiveJournal.parseMediaLink(content);
						if (media.preview) {
							background = 'style="background-image: url(' + media.preview + ');"';
						}

						iframe.setAttribute('lj-url', node.getAttribute('src'));
						iframe.setAttribute('data-link', content);
						iframe.setAttribute('lj-class', 'lj-iframe');
						iframe.setAttribute('class', 'lj-iframe-wrap lj-rtebox');
						iframe.setAttribute('style', "width: 490px; height:370px;");
						iframe.setAttribute('lj-style', "width: 480px; height:360px;");
						iframe.setAttribute('allowfullscreen', 'true');
						iframe.setAttribute('lj-content', encodeURIComponent("<div " + background + " class='lj-embed-inner lj-rtebox-inner'>" + (background ? "" : "iframe") + "</div>"));
					} else {
						iframe.setAttribute('lj-class', 'lj-embed');
						iframe.setAttribute('class', 'lj-embed-wrap lj-rtebox');
						iframe.setAttribute('lj-content', encodeURIComponent("<div " + background + " class='lj-embed-inner lj-rtebox-inner'>Embed</div>"));
					}
					iframe.setAttribute('lj-data', encodeURIComponent(LiveJournal.getEmbed(content)));


					iframe.setAttribute('frameBorder', 0);
					iframe.setAttribute('allowTransparency', 'true');
					iframe.setAttribute('lj-cmd', button);

					editor.insertElement(iframe);
					updateFrames();
				}

				LiveJournal.register_hook(widget + '_response', function(content) {
					insertEmbed(content);
				});

				editor.addCommand(button, {
					exec: function(editor) {
						var node = ljTagsData[button].node || lastSelectedIframe;

						if (node) {
							editor.rteButton(button, widget, {
								defaultText: node && decodeURIComponent(node.getAttribute('data-link') || node.getAttribute('lj-url') || node.getAttribute('lj-data')),
								editMode: true
							});
						} else {
							editor.rteButton(button, widget);
						}

					}
				});

				editor.ui.addButton(button, {
					label: CKLang.LJEmbed,
					command: button
				});
			})();

			// LJ Map
			(function() {
				var button = "LJMap",
					widget = "map";

				LiveJournal.register_hook('map_response', function(text) {
					var iframe = new CKEDITOR.dom.element('iframe', editor.document);

					var width = 425,
						height = 350,
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

						editor.rteButton(button, widget, {
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
								if (encloseNode && encloseNode.type === CKEDITOR.NODE_ELEMENT && encloseNode.is('iframe')) {
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

				if (!LJ.pageVar('remoteUser', true)) {
					return;
				}

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
							editor.rteButton(button, 'poll', {
								ljData: decodeURIComponent(node.getAttribute('lj-data')),
								editMode: true,
								disabled: node && (node.getAttribute('data-disabledPoll') ? true : false)
							});
						} else {
							editor.rteButton(button, 'poll');
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

				var btn;

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
							editor.rteButton(button, widget, {
								buttons: node.getAttribute('buttons'),
								editMode: true
							});
						} else {
							editor.rteButton(button, widget);
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

			// http://docs.cksource.com/CKEditor_3.x/Developers_Guide/Data_Processor

			// editor.dataProcessor.dataFilter: filter applied to the input data
			// when transforming it to HTML to be loaded into the editor ("on input").

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
					'iframe': function(element) {
						if (element.attributes['data-update'] === 'false') {
							return element;
						}

						var background = "";
						if (element.attributes['data-link']) {
							var media = LiveJournal.parseMediaLink(element.attributes['data-link']);
							if (media.preview) {
								background = 'style="background-image: url(' + media.preview + ');"';
							}
						}

						var src = element.attributes.src;

						if (element.attributes['lj-class'] && element.attributes['lj-class'].indexOf('lj-') + 1 == 1) {
							return element;
						}

						var fakeElement = new CKEDITOR.htmlParser.element('iframe'),
							frameStyle = '',
							bodyStyle = '',
							width = Number(element.attributes.width),
							height = Number(element.attributes.height);

						// partner iframe, fix width/height from style attribute
						if (element.attributes.src.indexOf('kroogi.com') !== -1 && element.attributes.style) {
							var matchWidth = element.attributes.style.match(/width:\s([0-9]+)px;/i),
								matchHeight = element.attributes.style.match(/height:\s([0-9]+)px;/i);

							if (matchHeight.length === 2 && matchWidth.length === 2) {
								width = Number(matchWidth.pop());
								height = Number(matchHeight.pop());
							}
						}

						if (!isNaN(width)) {
							frameStyle += 'width:' + width + 'px;';
							bodyStyle += 'width:' + (width - 10) + 'px;';
						}

						if (!isNaN(height)) {
							frameStyle += 'height:' + height + 'px;';
							bodyStyle += 'height:' + (height - 10) + 'px;';
						}

						if (frameStyle.length) {
							fakeElement.attributes['style'] = frameStyle;
							fakeElement.attributes['lj-style'] = bodyStyle;
						}

						fakeElement.attributes['lj-url'] = element.attributes.src ? encodeURIComponent(element.attributes.src) : '';
						fakeElement.attributes['lj-class'] = 'lj-iframe';
						fakeElement.attributes['class'] = 'lj-iframe-wrap lj-rtebox';
						fakeElement.attributes['lj-content'] = '<div ' + background + ' class="lj-rtebox-inner">' + (background ? '' : 'iframe') + '</div>';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						if (src != LiveJournal.getEmbed(decodeURIComponent(element.attributes.src))) {
							// convert iframe to embed
							fakeElement.attributes['lj-cmd'] = 'LJEmbedLink';
							fakeElement.attributes['data-link'] = element.attributes['data-link'];
						}

						return fakeElement;
					},
					a: function(element) {
						if (element.attributes['data-user']) {
							return;
						}

						if (element.parent && element.parent.attributes && !element.parent.attributes['lj:user']) {
							element.attributes['lj-cmd'] = 'LJLink2';
						}
					},
					img: function(element) {
						if (element.attributes['data-user']) {
							return;
						}
						var parent = element.parent && element.parent.parent;
						if (!parent || !element.attributes['data-user'] || !parent.attributes || !parent.attributes['data-user']) {
							element.attributes['lj-cmd'] = 'LJImage';
						}
					}
				}
			}, 5);

			// http://docs.cksource.com/CKEditor_3.x/Developers_Guide/Data_Processor

			// editor.dataProcessor.htmlFilter: filter applied to the HTML available in the
			// editor when transforming it on the XHTML outputted by the editor ("on output").

			dataProcessor.htmlFilter.addRules({
				elements: {
					'input': function(element) {
						if (element.attributes && element.attributes.id === '__focus') {
							return false;
						}
						return element;
					}
				}
			});

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
								var data = decodeURIComponent(element.attributes['lj-data']);

									newElement = new CKEDITOR.htmlParser.element('lj-embed');

									newElement.attributes.id = element.attributes.id;

									// necessary for isOptionalClose=true
									if (element.attributes.id) {
										newElement.isEmpty = true;
									}

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

								if (element.attributes['data-link']) {
									newElement.attributes['data-link'] = element.attributes['data-link'];
								}

								break;
							case 'lj-poll':
								var data = decodeURIComponent(element.attributes['lj-data']);
								newElement = new CKEDITOR.htmlParser.fragment.fromHtml(data).children[0];
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
											if (DFclassName && DFclassName.indexOf(className + '-close') + 1) {
												if (isCanBeNested && index) {
													index--;
												} else {
													newElement.next = node;
													break;
												}
											} else if (DFclassName && DFclassName.indexOf(className + '-open') + 1) {
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
