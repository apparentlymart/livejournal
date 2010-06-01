QotD = function(node)
{
	this.init(node);
}

QotD.prototype =
{
	skip: 1,
	ajax_params: {},
	
	init: function(node)
	{
		this.control = [
			jQuery('.i-qotd-nav-first', node).click(this.first.bind(this)),
			jQuery('.i-qotd-nav-prev', node).click(this.prev.bind(this)),
			jQuery('.i-qotd-nav-next', node).click(this.next.bind(this)),
			jQuery('.i-qotd-nav-last', node).click(this.last.bind(this))
		];
		
		if (!this.control[0][0]) { return }
		
		this.content_node = jQuery('.b-qotd-question', node);
		this.counter_node = jQuery('.qotd-counter', node);
		this.total = +jQuery('.i-qotd-nav-max', node).text();
		
		
		this.cache = new Array(this.total+1);
		
		this.ajax_params.domain = jQuery('#vertical_name').val() || 'homepage';
		
		var uselang = location.search.match(/[?&]uselang=([^&]+)/);
		if (uselang) {
			this.ajax_params.lang = uselang[1];
		}
	},
	
	first: function()
	{
		if (this.skip == this.total) { return }
		
		this.getQuestion(this.total);
	},
	
	prev: function()
	{
		if (this.skip == this.total) { return }
		
		this.getQuestion(this.skip+1);
	},
	
	next: function()
	{
		if (this.skip == 1) { return }
		
		this.getQuestion(this.skip-1);
	},
	
	last: function()
	{
		if (this.skip == 1) { return }
		
		this.getQuestion(1);
	},
	
	renderControl: function()
	{
		var method = this.skip == this.total ? 'addClass' : 'removeClass';
		this.control[0][method]('i-qotd-nav-first-dis');
		this.control[1][method]('i-qotd-nav-prev-dis');
		
		method = this.skip == 1 ? 'addClass' : 'removeClass';
		this.control[2][method]('i-qotd-nav-next-dis');
		this.control[3][method]('i-qotd-nav-last-dis');
	},
	
	getQuestion: function(new_skip)
	{
		this.cache[this.skip] = {
			// save DOM link for generated content, eg advertising.
			text: this.content_node,
			info: this.counter_node.html()
		}
		
		this.skip = new_skip;
		this.renderControl();
		
		this.cache[new_skip] ?
			this.setQuestion(this.cache[new_skip]) :
			jQuery.getJSON(
				LiveJournal.getAjaxUrl('qotd'),
				jQuery.extend(this.ajax_params, {skip : new_skip}),
				function(data)
				{
					this.skip == new_skip && this.setQuestion(data);
				}.bind(this)
			);
	},
	
	setQuestion: function(data)
	{
		this.content_node.hide();
		if (typeof data.text === 'string') {
			data.text = jQuery('<div/>', {'class': 'b-qotd-question', html: data.text})
				.insertAfter(this.content_node)
				.ljAddContextualPopup();
		}
		
		data.text.show();
		this.content_node = data.text;
		this.counter_node.html(data.info);
	}
}

jQuery(function($)
{
	$('.appwidget-qotd').each(function()
	{
		new QotD(this);
	});
});
