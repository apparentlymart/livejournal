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
		$('#updateForm').delegate('#draft', 'keypress click', updateDraftState).submit(function(ev) {
			isDirty = false;
		});

		//msie doesn't show all textarea content if width of textarea is equal to 100% (css).
		if (jQuery.browser.msie) {
			jQuery(function() {
				var draft = jQuery('#draft'),
					container = jQuery('#draft-container');

				var updateTextarea = function() {
					draft.css('width', 'auto');
					draft.width(container.width());
				};

				if (draft.length && container.length) {
					jQuery(window).resize(updateTextarea);
					updateTextarea();
				}
			});
		}

		window.onbeforeunload = confirmExit;
	};

	function confirmExit(ev) {
		if (isDirty) {
			return	Site.ml_text["entryform.close.confirm"] || "The page contains unsaved changes.";
		}
	}

	function normalizeValue(str) {
		return str.replace(/<br\s?\/>\n?/g, '\n').trim();
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

		if (processDraft) {
			checkDraftTimer();
		}
	}

	function initDraftData() {
		draftData = {
			textArea: $('#draft'),
			statusNode: $('#draftstatus')
		};

		draftData.lastValue = draftData.textArea.val();
		draftData.textArea.val(draftData.lastValue.replace(/<br\s?\/>\n?/g, '\n'));
	}

	window.initDraft = function(data) {
		initDraftData();

		for (var prop in data) {
			if (data.hasOwnProperty(prop)) {
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
			if (!CKEditor && CKEDITOR && CKEDITOR.env.isCompatible) {
				$.ajax({
					url: '/js/ck/contents.css?t=' + Site.version,
					success: function (data) {
						CKEDITOR.styleText = data;
					}
				});

				CKEDITOR.basePath = statPrefix + '/ck/';
				CKEDITOR.timestamp = Site.version;

				CKEDITOR.replace('draft', {
					skin: 'v2',
					baseHref: CKEDITOR.basePath,
					height: 350,
					language: Site.current_lang || 'en'
				}).on('instanceReady', function() {
						CKEditor = this;
						this.resetDirty();

						$('#updateForm')[0].onsubmit = function() {
							if (window.switchedRteOn) {
								var data = CKEditor.getData();
								if (!$('#event_format')[0].checked) {
									data = data.replace(/\r|\n/g, '<br />');
								}
								draftData.textArea.val(data);
							}
						};

						this.on('dialogHide', updateDraftState);
						this.on('afterCommandExec', updateDraftState);
						this.on('insertElement', updateDraftState);
						this.on('insertHtml', updateDraftState);
						this.on('insertText', updateDraftState);

						this.on('dataReady', function() {
							$('#entry-form-wrapper').attr('class', 'hide-html');
							this.container.show();
							this.element.hide();
							this.document.on('keypress', updateDraftState);
							this.document.on('click', updateDraftState);

							this.onSwitch = true;
							!CKEDITOR.env.ie && this.focus();

							$('#switched_rte_on').val('1');
							window.switchedRteOn = true;
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
				$('#switched_rte_on').val('1');
				window.switchedRteOn = true;
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

				CKEDITOR.note.hide(true);
				var data = CKEditor.getData().trim(); //also remove trailing spaces and newlines
				CKEditor.container.hide();
				CKEditor.element.show();

				CKEditor.element.setValue(data);
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
			minute = '0' + minute;
		}

		sec = date.getSeconds();
		if (sec < 10) {
			sec = '0' + sec;
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
