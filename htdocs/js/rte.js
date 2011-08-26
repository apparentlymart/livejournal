(function($, window) {
	window.switchedRteOn = false;

	var CKEditor,
		draftData,
		isDirty, //flag is true in case if user has unsaved text in the editor
		processDraft,
		lastValue;

	window.initEditor = function(data) {
		data = data || {};
		processDraft = !!('isInitDraft' in window);
		if (processDraft) {
			initDraft(data);
		} else {
			draftData = {
				textArea: $('#draft')
			};
		}

		lastValue = normalizeValue(draftData.textArea.val());
		$('#updateForm')
			.delegate('#draft', 'keypress click', updateDraftState)
			.submit(function(ev) {
				isDirty = false;
			} );

		window.onbeforeunload = confirmExit;
	}

	function confirmExit(ev) {
		if(isDirty) {
			return  Site.ml_text["entryform.close.confirm"] || "The page contains unsaved changes.";
		}
	}

	function normalizeValue(str) {
		return str
				.replace(/<br\s?\/>\n?/g, '\n')
				.replace(/\s+$/mg, '' )
				.trim();
	}

	function updateDraftState() {
		var value;

		setTimeout(function() {
			if (window.switchedRteOn && CKEditor) {
				value = CKEditor.getData();
			} else {
				value = draftData.textArea.val();
			}

			value = normalizeValue(value);
			isDirty = lastValue !== value;
		}, 0);

		if(processDraft) {
			checkDraftTimer();
		}
	}

	function initDraftData(){
		draftData = {
			textArea: $('#draft'),
			statusNode: $('#draftstatus')
		};
		
		draftData.lastValue = draftData.textArea.val();
		draftData.textArea.val(draftData.lastValue.replace(/<br\s?\/>\n?/g, '\n'));
	}

	window.initDraft = function(data) {
		initDraftData();

		for(var prop in data){
			if(data.hasOwnProperty(prop)){
				draftData[prop] = data[prop];
			}
		}

		if (draftData.ask && draftData.restoreData) {
			if (confirm(draftData.confirmMsg)) {
				draftData.lastValue = draftData.restoreData;
				draftData.textArea.val(draftData.lastValue);
				draftData.statusNode.val(draftData.draftStatus);
			}
		} else {
			draftData.statusNode.val('');
		}
	};

	window.useRichText = function (statPrefix) {
		if (!draftData) {
			initDraftData();
		}

		if (!window.switchedRteOn) {
			window.switchedRteOn = true;
			$('#switched_rte_on').val('1');

			if (!CKEditor && CKEDITOR && CKEDITOR.env.isCompatible) {
				CKEDITOR.basePath = statPrefix + '/ck/';
				var editor = CKEDITOR.replace('draft', {
					skin: 'v2',
					baseHref: CKEDITOR.basePath,
					height: 350,
					language: Site.current_lang || 'en'
				});

				editor.on('instanceReady', function() {
					CKEditor = editor;
					editor.resetDirty();

					$('#updateForm')[0].onsubmit = function() {
						if (window.switchedRteOn) {
							draftData.textArea.val(CKEditor.getData().replace(/(\r|\n)/g,'')); //we remove all newlines
						}
					};

					CKEditor.on('dataReady', function() {
						$('#entry-form-wrapper').attr('class', 'hide-html');

						CKEditor.container.show();
						CKEditor.element.hide();

						editor.on('dialogHide', updateDraftState);
						editor.on('afterCommandExec', updateDraftState);
						editor.on('insertElement', updateDraftState);
						editor.on('insertHtml', updateDraftState);
						editor.on('insertText', updateDraftState);
						editor.document.on('keypress', updateDraftState);
						editor.document.on('click', updateDraftState);
					});
				});
			} else {
				var data = CKEditor.element.getValue();

				var commands = CKEditor._.commands;
				for (var command in CKEditor._.commands) {
					if (commands.hasOwnProperty(command) && commands[command].state == CKEDITOR.TRISTATE_ON) {
						commands[command].setState(CKEDITOR.TRISTATE_OFF);
					}
				}

				CKEditor.setData(data);
			}
		}

		return false;
	};

	window.usePlainText = function() {
		if (!draftData) {
			initDraftData();
		}

		if (window.switchedRteOn) {
			window.switchedRteOn = false;
			$('#switched_rte_on').val('0');

			$('#entry-form-wrapper').attr('class', 'hide-richtext');
			if (CKEditor) {

				var data = CKEditor.getData().trim(); //also remove trailing spaces and newlines
				CKEditor.container.hide();
				CKEditor.element.show();

				// IE7 hack fix
				if ($.browser.msie && ($.browser.version == '7.0' || $.browser.version == '8.0')) {
					setTimeout(function() {
						CKEditor.element.setValue(data);
					}, 50);
				} else {
					CKEditor.element.setValue(data);
				}
			}

		}

		return false;
	};

	function checkDraftTimer() {
		if (draftData.timer) {
			draftData.timer = clearTimeout(draftData.timer);
		}

		if (!draftData.globalTimer) {
			draftData.globalTimer = setTimeout(saveDraft, draftData.interval * 1000);
		}

		draftData.timer = setTimeout(saveDraft, 3000);
	}

	function onSaveDraft() {
		var date = new Date();
		var hour, minute, sec, time;

		hour = date.getHours();
		if (hour >= 12) {
			time = ' PM';
		} else {
			time = ' AM';
		}

		if (hour > 12) {
			hour -= 12;
		} else if (hour == 0) {
			hour = 12;
		}

		minute = date.getMinutes();
		if (minute < 10) {
			minute = Number('0' + minute);
		}

		sec = date.getSeconds();
		if (sec < 10) {
			sec = Number('0' + sec);
		}

		draftData.statusNode.val(draftData.saveMsg.replace(/\[\[time\]\]/, hour + ':' + minute + ':' + sec + time + ' '));
	}

	function saveDraft() {
		var value = '';

		if (window.switchedRteOn && CKEditor) {
			if (CKEditor.checkDirty()) {
				CKEditor.resetDirty();
				value = CKEditor.getData();
			}
		} else if (draftData.textArea.length) {
			var currentValue = draftData.textArea.val();
			if (currentValue != draftData.lastValue) {
				value = currentValue;
			}
		}

		if (value.length) {
			value = normalizeValue(value);
			if (draftData.globalTimer) {
				draftData.globalTimer = clearTimeout(draftData.globalTimer);
			}

			draftData.lastValue = value;
			lastValue = value;
			isDirty = false;
			HTTPReq.getJSON({
				method: 'POST',
				url: '/tools/endpoints/draft.bml',
				onData: onSaveDraft,
				data: HTTPReq.formEncoded({
					saveDraft: value
				})
			});
		}
	}

})(jQuery, this);
