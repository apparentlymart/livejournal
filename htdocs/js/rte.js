(function($, window) {
	window.switchedRteOn = false;

	var CKEditor,
		draftData;

	window.initDraft = function(data) {
		draftData = data;

		data.lastValue = '';
		data.textArea = $('#draft');
		data.statusNode = $('#draftstatus');

		if (data.ask && data.restoreData) {
			if (confirm(data.confirmMsg)) {
				data.lastValue = data.restoreData;
				data.statusNode.val(data.draftStatus);
			}
		} else {
			data.statusNode.val('');
		}

		draftData.textArea.val(draftData.lastValue);

		$('#updateForm').delegate('#draft', 'keypress click', checkDraftTimer);
	};

	window.useRichText = function (statPrefix) {
		if (!window.switchedRteOn) {
			window.switchedRteOn = true;
			$('#switched_rte_on').value = '1';

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

					$('#updateForm').onsubmit = function() {
						if (window.switchedRteOn) {
							draftData.textArea.val(CKEditor.getData());
						}
					};

					CKEditor.on('dataReady', function() {
						$('#entry-form-wrapper').attr('class', 'hide-html');

						CKEditor.container.show();
						CKEditor.element.hide();

						editor.on('dialogHide', checkDraftTimer);
						editor.on('afterCommandExec', checkDraftTimer);
						editor.on('insertElement', checkDraftTimer);
						editor.on('insertHtml', checkDraftTimer);
						editor.on('insertText', checkDraftTimer);
						editor.document.on('keypress', checkDraftTimer);
						editor.document.on('click', checkDraftTimer);
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
		if (window.switchedRteOn) {
			window.switchedRteOn = false;
			$('#switched_rte_on').value = '0';

			if (CKEditor) {
				var data = CKEditor.getData();
				CKEditor.element.setValue(data);

				CKEditor.container.hide();
				CKEditor.element.show();
			}

			$('#entry-form-wrapper').attr('class', 'hide-richtext');
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
			if (draftData.globalTimer) {
				draftData.globalTimer = clearTimeout(draftData.globalTimer);
			}

			draftData.lastValue = value;
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