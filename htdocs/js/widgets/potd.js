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

jQuery(document).ready(function() {
	jQuery('div.appwidget-polloftheday form').live('submit', function(){
		var form = jQuery(this);
		jQuery('<i class="potd-preloader" />').appendTo('div.appwidget-polloftheday').height(jQuery('div.appwidget-polloftheday').height());
		var timer_reached = false,
			response_received = false;
		function checkStatus() {
			if (timer_reached && response_received) {
				if (jQuery('i.potd-preloader').length > 0) {
					jQuery('i.potd-preloader').remove();
				};
			}
		}
		setTimeout(function() {
			timer_reached = true;
			checkStatus();
		}, 1000);
		jQuery.post(form.attr('action'), form.serialize() + '&poll-submit=submit', function() {
			var skip = form.prev('input[name="skip"]').val();
			PotD.cache[skip] = null;
			PotD.getQuestion(form, skip);
			response_received = true;
			checkStatus();
		});
		return false;
	});
});
