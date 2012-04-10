(function($) {
	var user = LiveJournal.parseGetArgs().authas;

	window.selectModTags = function(node) {
		var widget = new LJWidgetIPPU_SelectTags({
			title: node.firstChild.nodeValue,
			height: 329,
			width: jQuery(window).width() / 2
		}, {
			user: user || jQuery(document.forms.authForm.authas).val()
		});

		return false;
	}

})(jQuery);

