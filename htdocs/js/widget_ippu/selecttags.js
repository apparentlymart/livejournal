LJWidgetIPPU_SelectTags = new Class( LJWidgetIPPU, {
	init: function (opts, params) {
		opts.widgetClass = 'IPPU::SelectTags';
		this.width = opts.width; // Use for resizing later
		this.height = opts.height; // Use for resizing later
		this.endpoint= "widget";
		this.method = "POST";
		LJWidgetIPPU_SelectTags.superClass.init.apply( this, arguments );

		this.ippu.setTitle( opts.title );
		this.ippu.addClass( 'ippu-select-tags' );
		this.ippu.setClickToClose(false)

		this._inputcall = new LJ.DelayedCall(this.input.bind(this), 200, true);
	},

	onRefresh: function() {
		var self = this;
		$('selecttags-all').value = $('prop_taglist').value.split(/ *, */).join(', ');

		this.checkboxes = jQuery('div.b-selecttags-tags input:checkbox', this.getWidget());
		this.boxesCache = {};
		this.checked = {};
		var cache = this.boxesCache,
			checked = this.checked;

		this.checkboxes.each(function() {
			cache[this.value] = this;

			if (this.checked) {
				checked[this.value] = true;
			}
		});

		jQuery('#selecttags-all').input(this._inputcall.run.bind(this._inputcall)).input();

		var container = jQuery(this.getWidget());
		if (container.length > 0) {
			container
				.delegate('div.b-selecttags-tags input', 'click', function(ev) {
					self.change(this);
				})
				.delegate('#selecttags-clear', 'click', this.reset_click.bind(this))
				.delegate('#selecttags-select', 'click', this.save_click.bind(this));
		}
	},

	change: function(node) {
		var inp = $('selecttags-all'),
			ary = inp.value.replace(/ */, '') ? inp.value.split(/ *, */) : [],
			i = -1,
			val = node.value;

		ary = jQuery.map(ary, function (val, idx) {
			return (val.length > 0) ? val : null
		});

		if (node.checked) {
			ary.push(val);
			this.checked[val] = true;
		} else {
			while (ary[++i]) {
				if (ary[i] == node.value) {
					ary.splice(i, 1);
					break;
				}
			}
			delete this.checked[val];
		}

		inp.value = ary.join(', ');
	},

	input: function() {
		var ary = $('selecttags-all').value.split(/ *, */),
			checkboxes = this.checkboxes,
			cache = this.boxesCache,
			newChecked = {},
			checked = this.checked;

		ary = ary.filter(function (val, idx) { return (val.length > 0); })
				.map(function(val){ return val.trim(); });

		ary.forEach(function(keyword) {
			keyword = keyword.trim();
			if (!cache.hasOwnProperty(keyword)) { return; }

			delete checked[keyword];
			cache[keyword].checked = true;
			newChecked[keyword] = true;
		});

		for(var keyword in checked) {
			cache[keyword].checked = false;
		}
		this.checked = newChecked;
	},

	save_click: function() {
		$('prop_taglist').value = $('selecttags-all').value.split(/ *, */).join(', ');
		this.close();
	},

	reset_click: function() {
		$('selecttags-all').value = '';
		this.checkboxes.attr('checked', false);
		this.checked = {};

		for (var keyword in this.boxesCache) {
			this.boxesCache[keyword].checked = false;
		}
	}
});

