QotD = function(node)
{
	this.init(node);
}

QotD.prototype =
{
	skip: 1,
	
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
		this.current_node = jQuery('.qotd-current', node);
		this.counter_node = jQuery('.qotd-counter', node);
		this.total = +jQuery('.i-qotd-nav-max', node).text();
		
		this.domain = jQuery('#vertical_name').val() || 'homepage';
		this.cache = [0, {
			text: this.content_node.html(),
			info: this.counter_node.html()
		}];
	},
	
	first: function()
	{
		if (this.skip == this.total) { return }
		
		this.skip = this.total;
		this.getQuestion();
	},
	
	prev: function()
	{
		if (this.skip == this.total) { return }
		
		this.skip++;
		this.getQuestion();
	},
	
	next: function()
	{
		if (this.skip == 1) { return }
		
		this.skip--;
		this.getQuestion();
	},
	
	last: function()
	{
		if (this.skip == 1) { return }
		
		this.skip = 1;
		this.getQuestion();
	},
	
	renederControl: function()
	{
		var method = this.skip == this.total ? 'addClass' : 'removeClass';
		this.control[0][method]('i-qotd-nav-first-dis');
		this.control[1][method]('i-qotd-nav-prev-dis');
		
		method = this.skip == 1 ? 'addClass' : 'removeClass';
		this.control[2][method]('i-qotd-nav-next-dis');
		this.control[3][method]('i-qotd-nav-last-dis');
		
		this.current_node.text(this.skip);
	},
	
	getQuestion: function()
	{
		this.renederControl();
		
		var skip = this.skip;
		this.cache[skip] ?
			this.setQuestion(this.cache[skip]) :
			jQuery.getJSON(
				LiveJournal.getAjaxUrl('qotd'),
				{skip: skip, domain: this.domain},
				function(data)
				{
					this.cache[skip] = data;
					this.skip == skip && this.setQuestion(data);
				}.bind(this)
			);
	},
	
	setQuestion: function(data)
	{
		this.content_node.html(data.text);
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
