function selectModTags(node) {
	var widget = new LJWidgetIPPU_SelectTags({
		title: node.firstChild.nodeValue,
		height: 329,
		width: jQuery(window).width() / 2
	}, {
		user: jQuery(document.forms.authForm.authas).val()
	});

	return false;
}

