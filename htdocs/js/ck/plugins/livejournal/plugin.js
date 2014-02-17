/*
 * Main LiveJournal plugin for CKEditor
 *
 * Contains helper methods, dataProcessor (input on output) configurations
 */
;(function($) {
	'use strict';

	CKEDITOR.processTextarea = true;

	/*
	 * @param {HTMLElement}	node		Parent node to traverse
	 * @param {Function}	callback	Callback, gets a current node as an argument
	 */
	function traverseTextNodes(node, callback) {
		var next;

		if (node.nodeType === 1) {
			if (node = node.firstChild) {
				do {
					next = node.nextSibling;
					traverseTextNodes(node, callback);
				} while(node = next);
		}

		} else if (node && node.nodeType === 3) {
			if (typeof callback === 'function') {
				callback(node);
			}
		}
	}

	/*
	 * @param	{String} html	HTML to process
	 * @return	{String}		Processed HTML
	 */
	var newlineToBr = (function() {

		var ignore = {
			'table': 1,
			'tbody': 1,
			'tr'   : 1,

			'lj-poll' : 1,
			'lj-pq'   : 1,

			'textarea': 1,

			'ul' : 1,
			'ol' : 1
		};

		return function(html) {
			var dom = jQuery('<div>' + html + '</div>');

			traverseTextNodes(dom.get(0), function(node) {
				if (node.parentNode && !ignore[node.parentNode.nodeName.toLowerCase()]) {
					$(node).replaceWith(function() {
						return node.nodeValue.replace(/\n/ig, '<br>');
					});
				}
			});

			return dom.html();
		};
	})();

	/*
	 * Remove unnecessary nbsp from HTML string
	 *
	 * @param	{String} html HTML to process
	 * @return	{String}
	 */
	function nbspFix(html) {
		html = html
			.replace(/\>&nbsp;\n/ig    , '>\n')
			.replace(/&nbsp;</ig       , ' <' )
			.replace(/\>&nbsp;/ig      , '> ' );

		return html;
	}

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
	jQuery.extend(CKLang, LJ.get('rtedata'));
	window.CKLang = CKEDITOR.CKLang = CKLang;

	// patch language
	CKEDITOR.lang.en.bold = LJ.ml('talk.insertbold');
	CKEDITOR.lang.en.italic = LJ.ml('talk.insertitalic');
	CKEDITOR.lang.en.underline = LJ.ml('talk.insertunderline');
	CKEDITOR.lang.en.strike = LJ.ml('talk.insertstrikethrough');
	CKEDITOR.lang.en.bulletedlist = LJ.ml('talk.bulletedlist');
	CKEDITOR.lang.en.numberedlist = LJ.ml('talk.numberedlist');
	CKEDITOR.lang.en.undo = LJ.ml('talk.undo');
	CKEDITOR.lang.en.redo = LJ.ml('talk.redo');

	CKEDITOR.styleText = Site.statprefix + '/js/ck/contents_new.css?t=' + Site.version;

	function rteButton(button, widget, options) {
		options = options || {};

		options && jQuery.extend(options, {
			fromDoubleClick: this.execFromEditor
		});

		LiveJournal.run_hook('rteButton', widget, jQuery('.cke_button_' + button), options);

		this.execFromEditor = false;
	}

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

	// https://jira.sup.com/browse/LJSV-2404
	CKEDITOR.dtd['lj-cut']['iframe'] = 1;
	CKEDITOR.dtd['lj-spoiler']['iframe'] = 1;

	CKEDITOR.plugins.add('livejournal', {
		init: function(editor) {
			editor.rteButton = rteButton;
			editor.ljTagsData = ljTagsData;

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

				LiveJournal.run_hook('rte_frame_load', this, iframeBody);

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

			/*
			 * Update frames
			 * Update is aborted if data-update or data-loaded is set on frame element.
			 *
			 * @param {string} [className] If provided, all frames with className will be updated.
			 */
			function updateFrames(className) {
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

					if (!className && frame.getAttribute('data-update') === 'false') {
						continue;
					}

					if (!className && doc && doc.body && doc.body.getAttribute('data-loaded')) {
						continue;
					}

					frame.removeListener('load', onLoadFrame);
					frame.on('load', onLoadFrame);
					doc.open();
					doc.write('<!DOCTYPE html>' +
						'<html style="width: 99%; height: 99%; overflow: hidden;">' +
							'<head><link rel="stylesheet" href="' + CKEDITOR.styleText + '" /></head>' +
							'<body data-loaded="true" scroll="no" class="' + (frame.getAttribute('lj-class') || '') + '" style="' + ljStyle + '" ' + (cmd ? ('lj-cmd="' + cmd + '"') : '') + '>' +
								decodeURIComponent(frame.getAttribute('lj-content') || '') +
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

			/*
			 * Focus transfomations
			 * @param {String} Html
			 * @return {String} Html with focus
			 */
			var transformFocus = (function() {
				var focusToken = '@focus@',
					focusTransformed = '<input type="hidden" id="__focus"/>';

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

				return function(html) {
					var position = Site.page.__htmlLast;
					if (typeof position === 'number') {

						if (html.indexOf('textarea') !== -1) {
							return html;
						}

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
					return html;
				};
			})();

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
					// from jQuery, with minor change for tags, containing '-'
					var rxhtmlTag = /<(?!area|br|col|embed|hr|img|input|link|meta|param)(([\w:-]+)[^>]*)\/>/gi;
					html = html.replace(rxhtmlTag, '<$1></$2>');

					html = transformFocus(html);

					html = newlineToBr(html);

					html = html.replace(/<lj [^>]*?>/gi, closeTag)
						.replace(/<lj-map [^>]*?>/gi, closeTag)
						.replace(/<lj-template[^>]*?>/gi, closeTag)
						.replace(/(<lj-cut[^>]*?)\/>/gi, '$1>')
						.replace(/<((?!br)[^\s>]+)([^>]*?)\/>/gi, '<$1$2></$1>')
						.replace(/<lj-poll.*?>[\s\S]*?<\/lj-poll>/gi, createPoll)
						.replace(/<lj-poll-([0-9]+)>/gi, createUneditablePoll)
						.replace(/<lj-repost\s*(?:button\s*=\s*(?:"([^"]*?)")|(?:"([^']*?)"))?.*?>([\s\S]*?)<\/lj-repost>/gi, createRepost)
						.replace(/<lj-embed(.*?)>([\s\S]*?)<\/lj-embed>/gi, createEmbed)
						.replace(/(<lj-raw.*?>)([\s\S]*?)(<\/lj-raw>)/gi, createLJRaw);

					html = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, html, fixForBody);

					if (CKEDITOR.env.ie) {
						html = '<xml:namespace ns="livejournal" prefix="lj" />' + html;
					}

					return html;
				};

				editor.dataProcessor.toDataFormat = function(html, fixForBody) {
					html = CKEDITOR.htmlDataProcessor.prototype.toDataFormat.call(this, html, fixForBody);

					html = nbspFix(html);

					html = html
						.replace(/<br\s*\/>/gi, '')
						.replace(/\t/g, ' ');

					var hookObject = {
						html: html
					};

					LiveJournal.run_hook('html_output', hookObject);

					return hookObject.html;
				};
			})();

			editor.dataProcessor.writer.indentationChars = '';
			editor.dataProcessor.writer.lineBreakChars   = '\n';

			['p', 'span', 'div', 'a', 'table', 'tbody', 'iframe',
			'lj', 'lj-cut', 'lj-spoiler',
			'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
			'lj-poll', 'lj-pq', 'lj-pi', 'ul', 'ol'].forEach(function(tag) {
				editor.dataProcessor.writer.setRules(tag, {
					indent           : false ,
					breakBeforeOpen  : false ,
					breakAfterOpen   : false ,
					breakBeforeClose : false ,
					breakAfterClose  : false
				});
			});

			['td', 'li'].forEach(function(tag) {
				editor.dataProcessor.writer.setRules(tag, {
					indent           : false ,
					breakBeforeOpen  : true  ,
					breakAfterOpen   : false ,
					breakBeforeClose : false ,
					breakAfterClose  : true
				});
			});

			['tr'].forEach(function(tag) {
				editor.dataProcessor.writer.setRules(tag, {
					indent           : false ,
					breakBeforeOpen  : true  ,
					breakAfterOpen   : true  ,
					breakBeforeClose : true  ,
					breakAfterClose  : true
				});
			});

			editor.on('selectionChange', findLJTags);
			editor.on('doubleclick', onDoubleClick);
			editor.on('afterCommandExec', updateFrames);
			editor.on('dialogHide', updateFrames);

			/*
			 * Fix paste by removing last line break,
			 * which occurs every time (LJSUP-14448).
			 */
			;(function() {
				var lastBr = /<br\s*\/?>$/i;
				editor.on('paste', function(e) {
					e.data.html = e.data.html.replace(lastBr, '');
				});
			})();

			/*
			 * Refresh frames after the paste
			 */
			editor.on('paste', function() {
				setTimeout(function() {
					updateFrames();
				}, 0);
			});

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
					label: LJ.ml('talk.insertmap'),
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
					label : LJ.ml('talk.justifyleft'),
					command : 'LJJustifyLeft'
				});
				editor.ui.addButton('LJJustifyCenter', {
					label : LJ.ml('talk.justifycenter'),
					command : 'LJJustifyCenter'
				});
				editor.ui.addButton('LJJustifyRight', {
					label : LJ.ml('talk.justifyright'),
					command : 'LJJustifyRight'
				});

				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, left));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, right));
				editor.on('selectionChange', CKEDITOR.tools.bind(onSelectionChange, center));
				editor.on('dirChanged', onDirChanged);
			})();
		},
		afterInit: function(editor) {
			var dataProcessor = editor.dataProcessor;

			// http://docs.cksource.com/CKEditor_3.x/Developers_Guide/Data_Processor

			// editor.dataProcessor.dataFilter: filter applied to the input data
			// when transforming it to HTML to be loaded into the editor ("on input").


			// process textareas
			if (CKEDITOR.processTextarea) {
				(function() {
					var rxTextarea = /(<textarea[^>]*>)([\s\S.]*)<\/textarea>/;

					LiveJournal.register_hook('html_output', function(hookObject) {
						hookObject.html =
							hookObject.html.replace(rxTextarea, function(_, tag, content) {
								content = content
								  .replace(/<br\/>/ig, '\n')
								  .replace(/\&#39;/ig, "'")
								  .replace(/\&quot;/ig, '"')
								  .replace(/\&amp;/ig, '&')

								  .replace(/\&lt;/ig, '<')
								  .replace(/\&gt;/ig, '>');

								return tag + content + "</textarea>";
							});
					});

					dataProcessor.dataFilter.addRules({
						elements: {
							'textarea': function(element) {
								element.children[0].value = unescape(
									element.children[0].value
										.replace('&lt;cke:encoded&gt;' , '')
										.replace('&lt;/cke:encoded&gt;', '')
								).replace(/<br\/>/ig, '\n');

								return element;
							}
						}
					});
				})();
			}


			dataProcessor.dataFilter.addRules({
				elements: {
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
						fakeElement.attributes['lj-attributes'] = encodeURIComponent(JSON.stringify(element.attributes));

						return fakeElement;
					},
					'iframe': function(element) {
						if (element.attributes['data-update'] === 'false') {
							return element;
						}

						function cssValue(attributeValue) {
							if (!attributeValue) {
								return 'auto';
							}

							return (/px|\%/).test(attributeValue) ?
									attributeValue :
									attributeValue.replace(
										attributeValue,
										attributeValue + 'px'
									);
						}

						var src = element.attributes.src;

						if (element.attributes['lj-class'] && element.attributes['lj-class'].indexOf('lj-') + 1 == 1) {
							return element;
						}

						var fakeElement = new CKEDITOR.htmlParser.element('iframe'),
							width = Number(element.attributes.width),
							height = Number(element.attributes.height);

						// partner iframe, fix width/height from style attribute
						if (element.attributes.src && element.attributes.src.indexOf('kroogi.com') !== -1 && element.attributes.style) {
							var matchWidth = element.attributes.style.match(/width:\s([0-9]+)px;/i),
								matchHeight = element.attributes.style.match(/height:\s([0-9]+)px;/i);

							if (matchHeight.length === 2 && matchWidth.length === 2) {
								width = Number(matchWidth.pop());
								height = Number(matchHeight.pop());
							}
						}

						fakeElement.attributes['style'] = String.prototype.supplant.call("width: {width}; height: {height};", {
							width: cssValue(element.attributes.width),
							height: cssValue(element.attributes.height)
						});
						fakeElement.attributes['lj-style'] = "width: 99%; height: 99%;";

						fakeElement.attributes['lj-url'] = element.attributes.src ? encodeURIComponent(element.attributes.src) : '';
						fakeElement.attributes['lj-class'] = 'lj-iframe';
						fakeElement.attributes['class'] = 'lj-iframe-wrap lj-rtebox';
						fakeElement.attributes['lj-content'] = '<div class="lj-rtebox-inner">iframe</div>';
						fakeElement.attributes['frameBorder'] = 0;
						fakeElement.attributes['allowTransparency'] = 'true';

						var media = LJ.Media.parse(decodeURIComponent(element.attributes.src));
						if (media) {
              media.done( function () {
                fakeElement.attributes['lj-cmd'] = 'LJEmbedLink';
                fakeElement.attributes['data-link'] = element.attributes['data-link'];
              })
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
							className = /lj-[a-z]+/i.exec(element.attributes['lj-class']);

						if (className) {
							className = className[0];
						} else {
							return element;
						}

						switch (className) {
							case 'lj-like':
								newElement = LiveJournal.run_hook('lj-like-output', element);
								break;
							case 'lj-embed':
								newElement = LiveJournal.run_hook('lj-embed-output', element);
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
									newElement.attributes[name.toLowerCase()] = parseInt(value, 10) + ((value.slice(-1) === '%') ? '%' : '');
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
								newElement.attributes = JSON.parse(encodeURIComponent(element.attributes['lj-attributes']));
								newElement.isOptionalClose = newElement.isEmpty = true;
							break;
							case 'lj-spoiler':
								newElement = LiveJournal.run_hook('lj-spoiler-output', element, className);
								break;
							case 'lj-cut':
								newElement = LiveJournal.run_hook('lj-cut-output', element, className);
								break;
							default:
								if (!element.children.length) {
									newElement = false;
								}
						}

						return newElement;
					},
					div: function(element) {
						if (editor.config.enterMode === CKEDITOR.ENTER_BR) {
							if (!element.children.length) {
								return false;
							}
						}

						if (editor.config.enterMode === CKEDITOR.ENTER_DIV) {
							delete element.name;
							element.add(new CKEDITOR.htmlParser.element('br'));
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
		}
	});


	/*
	 * CKEDITOR tests
	 */
	window.cktest = function() {
		var editor = CKEDITOR.instances.ck;

		var SAME = 1;

		var obj = [
			{
				input  : 'abc <lj user="test" /> ddd\n<lj user="6a" />',
				output : SAME
			},

			{
				input  : 'before<lj-like />after',
				output : SAME
			},

			{
				input  : 'abc\n\n<table>\n<tr>\n<td>123</td>\n</tr>\n</table>',
				output : 'abc\n\n<table><tbody>\n<tr>\n<td>123</td>\n</tr>\n</tbody></table>'
			},

			{
				input  : '<lj-like buttons="facebook, twitter"></lj-like>',
				output : '<lj-like buttons="facebook,twitter" />'
			},

			{
				input  : 'a<lj-like/>b',
				output : 'a<lj-like />b'
			},

			{
				input  : '<strike>abc <lj user="test" /> <b>bold</b></strike>',
				output : SAME
			},

			{
				input  : 'a<textarea>"dsg"\n<br>\nb</textarea>',
				output : SAME
			},

			{
				input  : '<textarea><style>.myClass:before {\ncontent: "ok" }</style></textarea>',
				output : SAME
			},

			{
				input  : "123<>\n<textarea>('<:&>')</textarea>\nabc\n<textarea>('<:&>')</textarea>\ndef",
				output : "123&lt;&gt;\n<textarea>('<:&>')</textarea>\nabc\n<textarea>('<:&>')</textarea>\ndef"
			}
		];

		var results = obj.map(function(test) {
			var data,
				result;

			editor.lightSetData(test.input);
			data = editor.getData();

			if (test.output !== SAME) {
				result = data === test.output;
			} else {
				result = data === test.input;
			}

			if (!result) {
				console.error('Input:    ' , test.input);
				console.error('Data:     ' , data);
				console.error('Expected: ' , test.output === SAME ? 'Same' : test.output);
			}

			return result;
		});

		// nbspFix test
		results.push(
			nbspFix("<b>1</b>&nbsp;<i>2</i> &nbsp; <div>3</div>\n&nbsp;<p>4</p>") ===
			"<b>1</b> <i>2</i> &nbsp; <div>3</div>\n <p>4</p>"
		);

		console.log(results);

		editor.lightSetData('');

		return results.every(function(element) { return element === true; });
	};

})(jQuery);
