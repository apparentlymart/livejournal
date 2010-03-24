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
		
		if (!this.control[0]) {
			return;
		}
		this.content = jQuery('.b-qotd-question', node);
		this.current_node = jQuery('.qotd-current', node);
		this.total = +jQuery('.qotd-total', node).text();
		
		this.domain = jQuery('#vertical_name').val() || 'homepage';
		this.cache = [null, this.content.html()];
	},
	
	first: function()
	{
		if (this.skip == this.total) { return }
		
		this.skip = this.total;
		this.getQuestions();
	},
	
	prev: function()
	{
		if (this.skip == this.total) { return }
		
		this.skip++;
		this.getQuestions();
	},
	
	next: function()
	{
		if (this.skip == 1) { return }
		
		this.skip--;
		this.getQuestions();
	},
	
	last: function()
	{
		if (this.skip == 1) { return }
		
		this.skip = 1;
		this.getQuestions();
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
	
	getQuestions: function()
	{
		this.renederControl();
		
		var skip = this.skip;
		this.cache[skip] ?
			this.content.html(this.cache[skip]) :
			jQuery.getJSON(
				LiveJournal.getAjaxUrl('qotd'),
				{skip: skip, domain: this.domain},
				function(data)
				{
					this.cache[skip] = data.text;
					this.skip == skip && this.content.html(data.text)
				}.bind(this)
			);
	}
}
jQuery(function($){
	$('.appwidget-qotd').each(function()
	{
		new QotD(this);
	});
})
