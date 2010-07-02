PotD =
{
	skip: 0,
	ajax_params: {
		_widget_class: 'PollOfTheDay',
		_widget_update: 1
	},
	pause: false,
	cache: [],
	
	init: function(node)
	{
		var uselang = location.search.match(/[?&]uselang=([^&]+)/);
		if (uselang) {
			this.ajax_params.lang = uselang[1];
		}
	},
	
	getQuestion: function(node, skip)
	{
		if (this.pause) {
			return;
		}
		this.pause = true;
		var widget_node = jQuery(node).parents('.appwidget');
		
		this.cache[skip] ?
			this.setQuestion(this.cache[skip], widget_node) :
			jQuery.getJSON(
				'/tools/endpoints/widget.bml',
				jQuery.extend(this.ajax_params, {
					skip: skip
				}),
				function(data)
				{
					this.setQuestion(data._widget_body, widget_node, skip);
				}.bind(this)
			);
	},
	
	setQuestion: function(html, node, skip)
	{
		if (typeof html === 'string') {
			html = jQuery('<div/>', {html: html})
				.prependTo(node)
				.ljAddContextualPopup();
			// save DOM link for generated content, eg advertising.
			this.cache[skip] = html;
		}
		node.children().hide();
		html.show();
		this.pause = false;
	}
}

PotD.init();
