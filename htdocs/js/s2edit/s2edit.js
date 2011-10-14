// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2edit.js - main editor declarations
// ---------------------------------------------------------------------------

var s2index;

var s2dirty;
var s2lineCount;

var s2edit = function() {
	return {
		init: function(widget) {
			this.widget = widget;
			this.widget.onData = this.drawCompileResults.bind(this);

			s2dirty = 1;
			s2lineCount = 0;

			s2initIndex();
			s2initParser();
			s2initSense();
			s2buildReference();
			s2initDrag();

			s2output.init();

			// Disable selection in the document (IE only - prevents wacky dragging bugs)
			document.onselectstart = function () { return false; };
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
