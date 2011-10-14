define('ace/mode/s2', function(require, exports, module) {

var oop = require("pilot/oop");
var TextMode = require("ace/mode/perl").Mode;
var Tokenizer = require("ace/tokenizer").Tokenizer;
var S2HighlightRules = require("ace/mode/s2_highlight_rules").S2HighlightRules;
var MatchingBraceOutdent = require("ace/mode/matching_brace_outdent").MatchingBraceOutdent;

var Mode = function() {
	this.$tokenizer = new Tokenizer(new S2HighlightRules().getRules());
    this.$outdent = new MatchingBraceOutdent();
};
oop.inherits(Mode, TextMode);

exports.Mode = Mode;
});

define('ace/mode/s2_highlight_rules', function(require, exports, module) {

var oop = require("pilot/oop");
var lang = require("pilot/lang");
var TextHighlightRules = require("ace/mode/text_highlight_rules").TextHighlightRules;

var S2HighlightRules = function() {
		var stringfill = {
			token : "string",
			merge : true,
			regex : ".+"
		};

	var keywords = lang.arrayToMap(
		("propgroup|property|layerinfo|use|set|function|var|return|class|" +
		 "if|elseif|else|foreach|isnull|defined|new|null|reverse|size|extends|print").split("|")
	);

	var builtinFunctions = lang.arrayToMap(
		("alternate|clean_url|control_strip_logged_out_full_userpic_css|" +
		 "control_strip_logged_out_userpic_css|ehtml|end_css|etags|eurl|get_page|" + 
		 "get_plural_phrase|get_url|get_url|htmlattr|htmlattr|int|journal_current_datetime|" + 
		 "lang_at_datetime|lang_map_plural|lang_metadata_title|lang_ordinal|lang_ordinal|" + 
		 "lang_page_of_pages|lang_user_wrote|lang_viewname|pageview_unique_string|" + 
		 "palimg_gradient|palimg_modify|palimg_tint|print_custom_control_strip_css|" +
		 "print_stylesheet|prop_init|rand|secs_to_string|server_sig|set_content_type|" +
		 "set_handler|start_css|string|striphtml|style_is_active|userinfoicon|userlite_as_string|" +
		 "userlite_base_url|viewer_is_friend|viewer_is_member|viewer_is_owner|viewer_logged_in|" +
		 "viewer_sees_ads|viewer_sees_control_strip|viewer_sees_ebox|viewer_sees_hbox_bottom|" +
		 "viewer_sees_hbox_top|viewer_sees_vbox|weekdays|zeropad|" +
		 "bool|Color|Comment|CommentInfo|Date|DateTime|DayPage|Entry|EntryLite|EntryPage|Friend|" +
		 "FriendsPage|Image|int|ItemRange|Link|MessagePage|MonthDay|MonthEntryInfo|MonthPage|" +
		 "Page|PalItem|RecentNav|RecentPage|Redirector|ReplyForm|ReplyPage|string|Tag|TagDetail|" +
		 "TagsPage|User|UserLink|UserLite|YearDay|YearMonth|YearPage|YearWeek|YearYear").split("|")
	);

	this.$rules = {
		start : [
			{
				token : "comment",
				regex : "#.*$"
			}, {
				token : "string",
				merge : true,
				regex : '"""',
				next : "qqstring"
			}, {
				token : "string", // single line
				regex : '["](?:(?:\\\\.)|(?:[^"\\\\]))*?["]'
			}, {
				token : "constant.numeric", // hex
				regex : "0[xX][0-9a-fA-F]+\\b"
			}, {
				token : "constant.numeric", // float
				regex : "[+-]?\\d+(?:(?:\\.\\d*)?(?:[eE][+-]?\\d+)?)?\\b"
			}, {
				token : "constant.language.boolean",
				regex : "(?:true|false)\\b"
			}, {
				token : function(value) {
					if (builtinFunctions.hasOwnProperty(value))
						return "support.function";
					else if (keywords.hasOwnProperty(value))
						return "keyword";
					else if(value.match(/^(\$[a-zA-Z_][a-zA-Z0-9_]*)$/))
						return "variable";
					return "identifier";
				},
				regex : "[a-zA-Z_$][a-zA-Z0-9_$]*\\b"
			}, {
				token : "keyword.operator",
				regex : "%|\\*|\\-\\-|\\-|\\+\\+|\\+|==|=|!=|!==|<=|>=|<|>|\\?\\:|\\?|:|\\/|\\b(?:instanceof|isa|as|and|or|not)"
			}, {
				token : "lparen",
				regex : "[[({]"
			}, {
				token : "rparen",
				regex : "[\\])}]"
			}, {
				token : "text",
				regex : "\\s+"
			}],
			
			qqstring : [{
				token : "string",
				regex : '.*?"""',
				next : "start"
			}, stringfill]
		};
};

oop.inherits(S2HighlightRules, TextHighlightRules);

exports.S2HighlightRules = S2HighlightRules;
});

define('ace/commands/autocompletion', function(require, exports, module) {

var canon = require("pilot/canon");

function bindKey(win, mac) {
	return {
		win: win,
		mac: mac,
		sender: "editor"
	};
}

//all these default shortcuts override browser hotkeys, disable them
canon.removeCommand('transposeletters');
canon.removeCommand('centerselection');
canon.removeCommand('removetolineend');
canon.removeCommand('find');
canon.removeCommand('findprevious');
canon.removeCommand('findnext');
canon.removeCommand('gotoline');
canon.removeCommand('removeline');
canon.removeCommand('replace');
canon.removeCommand('replaceall');

canon.addCommand({
	name: "indent",
	bindKey: bindKey("Tab", "Tab"),
	exec: function(env, args, request) {
		if (!s2sense('\t'.charCodeAt(0))) {
			env.editor.indent();
		}
	}
});

});
