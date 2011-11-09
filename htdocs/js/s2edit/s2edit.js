// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2edit.js - main editor declarations
// ---------------------------------------------------------------------------

var s2index;

var s2dirty;
var s2lineCount;
var s2settings;

var s2edit = function() {
	return {
		init: function(widget) {
			this.widget = widget;
			this.widget.onData = this.drawCompileResults.bind(this);

			s2dirty = 1;
			s2lineCount = 0;

			this.initSettings();
			this.initGui();

			s2initIndex();
			s2initParser();
			s2initSense();
			s2buildReference();
			s2initDrag();

			s2output.init();

			// Disable selection in the document (IE only - prevents wacky dragging bugs)
			document.onselectstart = function () { return false; };

			if (!this.isAceSupported()) { return; }

			this.aceInit();
		},

		initSettings: function() {
			var settings = jQuery.storage.getItem('s2edit') || {};

			s2settings = {
				load: function(item) {
					return settings[item] || void 0;
				},

				save: function(item, val) {
					//do nothing if option has the same value
					if (settings.hasOwnProperty(item) && settings[item] === val) { return; }

					settings[item] = val;
					jQuery.storage.setItem('s2edit', settings);
				},

				turboEnabled: function() {
					return !!this.load('turboMode')
				}
			};
		},

		initGui: function() {
			var self = this,
				turboButton = jQuery('.turbo-mode'),
				toggleTurboButton = function(enable) {
					if (enable) {
						turboButton.val('Back to old editor');
					} else {
						turboButton.val('Show new editor');
					}
				};

			turboButton.click(function(ev) {
				var modeEnabled = !s2settings.load('turboMode');
				s2settings.save('turboMode', modeEnabled);
				toggleTurboButton(modeEnabled);
				if (modeEnabled) {
					if (!s2isAceActive()) {
						self.toggleEditor();
					}
				} else {
					if (s2isAceActive()) {
						self.toggleEditor();
					}
				}
			});

			var modeEnabled = !!s2settings.load('turboMode');
			toggleTurboButton(modeEnabled);
		},

		isAceSupported: function() {
			return !(jQuery.browser.opera || (jQuery.browser.msie && jQuery.browser.version));
		},

		aceInit: function() {
			var textarea = jQuery('#main'),
				pre = jQuery('<pre id="editor"/>')
					.addClass('maintext')
					.hide()
					.insertAfter(textarea);

			if (!s2settings.load('useAce')) { return; }

			this.toggleEditor();
		},

		toggleEditor: function() {
			if (!this.isAceSupported()) { return; }
			var textarea = jQuery('#main'),
				editorEl = jQuery('#editor');

			if (!s2isAceActive()) {
				textarea.hide();
				editorEl.show();

				if (!window.aceEditor) {
					var editor = window.aceEditor = ace.edit("editor");
					editor.setTheme("ace/theme/textmate");
					require('ace/commands/autocompletion');

					var S2Mode = require("ace/mode/s2").Mode;
					editor.getSession().setMode(new S2Mode());
					editor.getSession().addEventListener("change", function(e) {
						s2dirty = 1;

						if (e.data.action === 'insertText' && e.data.text.length === 1) {
							s2sense(e.data.text.charCodeAt(0));
						}
					});
				}

				aceEditor.getSession().setValue(textarea.val());
				s2settings.save('useAce', true);
			} else {
				textarea.val(aceEditor.getSession().getValue());
				textarea.show();
				editorEl.hide();
				s2settings.save('useAce', false);
			}
		},

		save: function(text) {
			s2output.add('Compiling..', true);
			this.widget.saveContent(text);
		},

		drawCompileResults: function(data) {
			s2output.add(data.res.build, true);
		}
	}
}();


function s2initIndex()
{
	s2index = new Object();
}
