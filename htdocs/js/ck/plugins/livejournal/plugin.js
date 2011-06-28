var flashFilenameRegex = /\.swf(?:$|\?)/i;

function isFlashEmbed(element){
	var attributes = element.attributes;

	return ( attributes.type == 'application/x-shockwave-flash' || flashFilenameRegex.test(attributes.src || '') );
}

function createFakeElement(editor, realElement){
	return editor.createFakeParserElement(realElement, 'lj-embed', 'livejournal', false);
}

CKEDITOR.plugins.add('livejournal', {
	init: function(editor){
		editor.dataProcessor.toHtml = function(data, fixForBody){
			data = top.convertToHTMLTags(data); // call from rte.js

			data = data.replace(/<lj-cut([^>]*)><\/lj-cut>/g, '<lj-cut$1>\ufeff</lj-cut>')
				.replace(/(<lj-cut[^>]*>)/g, '\ufeff$1').replace(/(<\/lj-cut>)/g, '$1\ufeff');

			// IE custom tags. http://msdn.microsoft.com/en-us/library/ms531076%28VS.85%29.aspx
			if(CKEDITOR.env.ie){
				data = data.replace(/<lj-cut([^>]*)>/g, '<lj:cut$1>').replace(/<\/lj-cut>/g, '</lj:cut>')
					.replace(/<([\/])?lj-raw>/g, '<$1lj:raw>').replace(/<([\/])?lj-wishlist>/g, '<$1lj:wishlist>')
					.replace(/(<lj [^>]*)> /g, '$1> '); // IE merge spaces
			} else {
				// close <lj user> tags
				data = data.replace(/(<lj [^>]*[^\/])>/g, '$1/> ');
			}

			if(!$('event_format').checked){
				data = data.replace(/\n/g, '<br />');
			}

			data = CKEDITOR.htmlDataProcessor.prototype.toHtml.call(this, data, fixForBody);
			return data;
		};

		editor.dataProcessor.toDataFormat = function(html, fixForBody){
			// DOM methods are used for detection of node opening/closing
			/*var document = editor.document.$;
			var newBody = document.createElement('div'),
				copyNode = document.body.firstChild;
			if(copyNode){
				newBody.appendChild(copyNode.cloneNode(true));
				while(copyNode = copyNode.nextSibling){
					newBody.appendChild(copyNode.cloneNode(true));
				}
				var divs = newBody.getElementsByTagName('div'),
					i = divs.length;
				while(i--){
					var div = divs[i];
					switch(div.className){
						// lj-template any name: <lj-template name="" value="" alt="html code"/>
						case 'lj-template':
							var name = div.getAttribute('name'),
								value = div.getAttribute('value'),
								alt = div.getAttribute('alt');
							if(!name || !value || !alt){
								break;
							}
							var ljtag = FCK.EditorDocument.createElement('lj-template');
							ljtag.setAttribute('name', name);
							ljtag.setAttribute('value', value);
							ljtag.setAttribute('alt', alt);
							div.parentNode.replaceChild(ljtag, div);
					}

				}
			}*/

			html = CKEDITOR.htmlDataProcessor.prototype.toDataFormat.call(this, html, fixForBody);
			html = html.replace(/\t/g, ' ');
			// rte fix, http://dev.fckeditor.net/ticket/3023
			// type="_moz" for Safari 4.0.11
			if(!CKEDITOR.env.ie){
				html = html.replace(/<br (type="_moz" )? ?\/>$/, '');
				if(CKEDITOR.env.webkit){
					html = html.replace(/<br type="_moz" \/>/, '');
				}
			}

			html = convertToLJTags(html); // call from rte.js
			if(!$('event_format').checked && !top.switchedRteOn){
				html = html.replace(/\n?\s*<br \/>\n?/g, '\n');
			}

			// IE custom tags
			if(CKEDITOR.env.ie){
				html = html.replace(/<lj:cut([^>]*)>/g, '<lj-cut$1>').replace(/<\/lj:cut>/g, '</lj-cut>')
					.replace(/<([\/])?lj:wishlist>/g, '<$1lj-wishlist>').replace(/<([\/])?lj:raw>/g, '<$1lj-raw>');
			}

			html = html.replace(/><\/lj-template>/g, '/>');// remove null pointer.replace(/\ufeff/g, '');

			return html;
		};

		//////////  LJ User Button //////////////
		var url = window.parent.Site.siteroot + '/tools/endpoints/ljuser.bml',
			LJUserNode;

		editor.attachStyleStateChange(new CKEDITOR.style({
			element: 'span'
		}), function(){
			var selectNode = editor.getSelection().getStartElement().getAscendant('span', true);
			var isUserLink = selectNode && selectNode.hasClass('ljuser');
			LJUserNode = isUserLink ? selectNode : null;
			editor.getCommand('LJUserLink').setState(isUserLink ? CKEDITOR.TRISTATE_ON : CKEDITOR.TRISTATE_OFF);
		});

		editor.on('doubleclick', function(evt){
			var command = editor.getCommand('LJUserLink');
			LJUserNode = evt.data.element.getAscendant('span', true);
			if(LJUserNode && LJUserNode.hasClass('ljuser')){
				command.setState(CKEDITOR.TRISTATE_ON);
				command.exec();
				evt.data.dialog = '';
			} else {
				command.setState(CKEDITOR.TRISTATE_OFF);
			}
		});

		editor.addCommand('LJUserLink', {
			exec : function(editor){
				var userName = '',
					selection = editor.getSelection(),
					LJUser = LJUserNode;

				if(this.state == CKEDITOR.TRISTATE_ON && LJUserNode){
					userName = prompt(window.parent.CKLang.UserPrompt, LJUserNode.getElementsByTag('b').getItem(0).getText());
				} else if(selection.getType() == 2){
					userName = selection.getSelectedText();
				}

				if(userName == ''){
					userName = prompt(window.parent.CKLang.UserPrompt, userName);
				}

				if(!userName){
					return;
				}

				parent.HTTPReq.getJSON({
					data: parent.HTTPReq.formEncoded({
						username : userName
					}),
					method: 'POST',
					url: url,
					onData: function(data){
						if(data.error){
							alert(data.error);
							return;
						}
						if(!data.success){
							return;
						}
						data.ljuser = data.ljuser.replace('<span class="useralias-value">*</span>', '');

						if(LJUser){
							LJUser.setHtml(data.ljuser);
							LJUser.insertBeforeMe(LJUser.getFirst());
							LJUser.remove();
						} else {
							editor.insertHtml(data.ljuser + '&nbsp;');
						}
					}
				});
			}
		});

		editor.ui.addButton('LJUserLink', {
			label: window.parent.CKLang.LJUser,
			command: 'LJUserLink'
		});

		//////////  LJ Embed Media Button //////////////
		editor.addCommand('LJEmbedLink', {
			exec: function(){
				top.LJ_IPPU.textPrompt(window.parent.CKLang.LJEmbedPromptTitle, window.parent.CKLang.LJEmbedPrompt, do_embed);
			}
		});

		editor.ui.addButton('LJEmbedLink', {
			label: window.parent.CKLang.LJEmbed,
			command: 'LJEmbedLink'
		});

		editor.addCss('img.lj-embed' +
			'{' +
				'background-image: url(' + CKEDITOR.getUrl(this.path + 'images/placeholder_flash.png') + ');' +
				'background-position: center center;' +
				'background-repeat: no-repeat;' +
				'border: 1px solid #a9a9a9;' +
				'width: 80px;' +
				'height: 80px;' +
			'}');

		function do_embed(content){
			if(content && content.length){
				editor.insertHtml('<div class="ljembed">' + content + '</div><br/>');
				editor.focus();
			}
		}

		//////////  LJ Cut Button //////////////
		var ljCutNode;
		
		editor.attachStyleStateChange(new CKEDITOR.style({
			element: 'lj-cut'
		}), function(state){
			var command = editor.getCommand('LJCut');
			command.setState(state);
			if(state == CKEDITOR.TRISTATE_ON){
				ljCutNode = this.getSelection().getStartElement().getAscendant('lj-cut', true);
			} else {
				ljCutNode = null;
			}
		});

		editor.on('doubleclick', function(evt){
			var command = editor.getCommand('LJCut');
			ljCutNode = evt.data.element.getAscendant('lj-cut', true);
			if(ljCutNode){
				command.setState(CKEDITOR.TRISTATE_ON);
				command.exec();
			} else {
				command.setState(CKEDITOR.TRISTATE_OFF);
			}
		});

		editor.addCommand('LJCut', {
			exec: function(){
				var text;
				if(this.state == CKEDITOR.TRISTATE_ON){
					text = prompt(window.parent.CKLang.CutPrompt, ljCutNode.getAttribute('text') || top.CKLang.ReadMore);
					if(text){
						if(text == window.parent.CKLang.ReadMore){
							ljCutNode.removeAttribute('text');
						} else {
							ljCutNode.setAttribute('text', text);
						}
					}
				} else {
					text = prompt(window.parent.CKLang.CutPrompt, window.parent.CKLang.ReadMore);
					if(text){
						ljCutNode = editor.document.createElement('lj-cut');
						if(text != window.parent.CKLang.ReadMore){
							ljCutNode.setAttribute('text', text);
						}
						editor.getSelection().getRanges()[0].extractContents().appendTo(ljCutNode);
						editor.insertElement(ljCutNode);
					}
				}
			}
		});

		editor.ui.addButton('LJCut', {
			label: window.parent.CKLang.LJCut,
			command: 'LJCut'
		});

		//////////  LJ Poll Button //////////////
		if(top.canmakepoll){
			var currentPollForm, currentPoll;
			var noticeHtml = window.parent.CKLang
				.Poll_PollWizardNotice + '<br /><a href="#" onclick="CKEDITOR.instances.draft.getCommand(\'LJPollLink\').exec(); return false;">' + window
				.parent.CKLang.Poll_PollWizardNoticeLink + '</a>';

			editor.attachStyleStateChange(new CKEDITOR.style({
				element: 'form',
				attributes: {
					'class': 'ljpoll'
				}
			}), function(state){
				var command = editor.getCommand('LJPollLink');
				command.setState(state);
				currentPollForm = this.getSelection().getStartElement().getAscendant('form', true);
				currentPollForm = currentPollForm && currentPollForm.hasClass('ljpoll') ? currentPollForm.$ : null;
				if(state == CKEDITOR.TRISTATE_ON){
					parent.LJ_IPPU.showNote(noticeHtml, editor.container.$).centerOnWidget(editor.container.$);
				}
			});

			editor.on('doubleclick', function(evt){
				var command = editor.getCommand('LJPollLink');
				currentPollForm = evt.data.element.getAscendant('form', true);
				if(currentPollForm && currentPollForm.hasClass('ljpoll')){
					command.setState(CKEDITOR.TRISTATE_ON);
					command.exec();
					evt.data.dialog = '';
				} else {
					command.setState(CKEDITOR.TRISTATE_OFF);
				}
			});

			CKEDITOR.dialog.add('LJPollDialog', function(){
				var isAllFrameLoad = 0, okButtonNode, questionsWindow, setupWindow;

				var onLoadPollPage = function(){
					if(this.removeListener){
						this.removeListener('load', onLoadPollPage);
					}
					if(isAllFrameLoad && okButtonNode){
						currentPoll = new Poll(currentPollForm && unescape(currentPollForm
							.getAttribute('data')), questionsWindow.document, setupWindow.document, questionsWindow.Questions);

						questionsWindow.ready(currentPoll);
						setupWindow.ready(currentPoll);
						
						okButtonNode.style.display = 'block';
					} else {
						isAllFrameLoad++;
					}
				};

				return {
					title : window.parent.CKLang.Poll_PollWizardTitle,
					width : 420,
					height : 270,
					onShow: function(){
						if(isAllFrameLoad){
							currentPoll = new Poll(currentPollForm && unescape(currentPollForm.getAttribute('data')), questionsWindow
								.document, setupWindow.document, questionsWindow.Questions);

							questionsWindow.ready(currentPoll);
							setupWindow.ready(currentPoll);
						}
					},
					contents : [
						{
							id : 'LJPool_Setup',
							label : 'Setup',
							padding: 0,
							elements :[
								{
									type : 'html',
									html : '<iframe src="/tools/ck_poll_setup.bml" frameborder="0" style="width:100%; height:370px"></iframe>',
									onShow: function(data){
										if(!okButtonNode){
											(okButtonNode = document.getElementById(data.sender.getButton('LJPool_Ok').domId).parentNode)
												.style.display = 'none';
										}
										var iframe = this.getElement('iframe');
										setupWindow = iframe.$.contentWindow;
										if(setupWindow.ready){
											onLoadPollPage();
										} else {
											iframe.on('load', onLoadPollPage);
										}
									}
								}
							]
						},
						{
							id : 'LJPool_Questions',
							label : 'Questions',
							padding: 0,
							elements:[
								{
									type : 'html',
									html : '<iframe src="/tools/ck_poll_questions.bml" frameborder="0" style="width:100%; height:370px"></iframe>',
									onShow: function(){
										var iframe = this.getElement('iframe');
										questionsWindow = iframe.$.contentWindow;
										if(questionsWindow.ready){
											onLoadPollPage();
										} else {
											iframe.on('load', onLoadPollPage);
										}
									}
								}
							]
						}
					],
					buttons : [new CKEDITOR.ui.button({
						type : 'button',
						id : 'LJPool_Ok',
						label : editor.lang.common.ok,
						onClick : function(evt){
							evt.data.dialog.hide();
							var pollSource = new Poll(currentPoll, questionsWindow.document, setupWindow.document, questionsWindow.Questions).outputHTML();
							if(pollSource.length > 0){
								if(currentPollForm){
									var node = document.createElement('div');
									node.innerHTML = pollSource;
									currentPollForm.$.parentNode.insertBefore(node.firstChild, currentPollForm.$);
									currentPollForm.remove();
								} else {
									editor.insertHtml(pollSource);
								}
								currentPollForm = null;
							}
						}
					}), CKEDITOR.dialog.cancelButton]
				};
			});

			editor.addCommand('LJPollLink', new CKEDITOR.dialogCommand('LJPollDialog'));
		} else {
			editor.addCommand('LJPollLink', {
				exec: function(editor){
					var notice = top.LJ_IPPU.showNote(window.parent.CKLang.Poll_AccountLevelNotice, editor.container.$);
					notice.centerOnWidget(editor.container.$);
				}
			});

			editor.getCommand('LJPollLink').setState(CKEDITOR.TRISTATE_DISABLED);
		}

		editor.ui.addButton('LJPollLink', {
			label: window.parent.CKLang.Poll,
			command: 'LJPollLink'
		});
	},
	afterInit : function(editor){

		//////////  LJ Embed Media Button //////////////
		var dataProcessor = editor.dataProcessor,
			dataFilter = dataProcessor && dataProcessor.dataFilter;

		if(dataFilter){
			dataFilter.addRules({
				elements : {
					'cke:object' : function(element){
						var attributes = element.attributes,
							classId = attributes.classid && String(attributes.classid).toLowerCase();

						if(!classId && !isFlashEmbed(element)){
							for(var i = 0; i < element.children.length; i++){
								if(element.children[ i ].name == 'cke:embed'){
									if(!isFlashEmbed(element.children[ i ]))
										return null;

									return createFakeElement(editor, element);
								}
							}
							return null;
						}

						return createFakeElement(editor, element);
					},

					'cke:embed' : function(element){
						if(!isFlashEmbed(element))
							return null;

						return createFakeElement(editor, element);
					}
				}
			}, 5);
		}
	},

	requires : [ 'fakeobjects' ]
});
