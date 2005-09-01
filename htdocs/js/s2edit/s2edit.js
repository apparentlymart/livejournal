// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2edit.js - main editor declarations
// ---------------------------------------------------------------------------

var s2index;

var s2dirty;
var s2lineCount;

function s2init()
{
	s2dirty = 1;
	s2lineCount = 0;

	s2initIndex();
	s2initParser();
	s2initSense();
	s2buildReference();
	s2initDrag();
}

function s2initIndex()
{
	s2index = new Object();
}
