var Photos2HomepageWidget = {
	init: function(){
		var widget = jQuery('.appwidget-photos2homepage');
		this.controls = {
			prev: widget.find('.i-potd-nav-prev'),
			next: widget.find('.i-potd-nav-next')
		};

		var images = this.images = [];
		widget.find('.pic-list > li').each(function(){
			images.push({
				img: this.getElementsByTagName('img')[0],
				link: this.getElementsByTagName('a')[0],
				li: this
				});
		});

		this.page = 1;
		this.pages = Math.ceil( photos2homepage.length / photos_per_page );
		this.ppCount = photos_per_page;

		//preload thumbnails
		this.imageHash = [];
		for( var i = 0; i < photos2homepage.length; ++i){
			this.imageHash[ i ] = new Image();
			this.imageHash[ i ].src = photos2homepage[ i ].src;
		}
	},

	prev: function(){
		if(this.page == 1) return;
		this.page--;
		this._updatePager();
	},

	next: function(){
		if(this.page == this.pages) return;
		this.page++;
		this._updatePager();
	},

	_updatePager: function(){
		this.controls.prev[(this.page == 1)?"addClass":"removeClass"]('i-potd-nav-prev-dis');
		this.controls.next[(this.page == this.pages)?"addClass":"removeClass"]('i-potd-nav-next-dis');

		var idx = 0;
		for( var i = 0; i < this.ppCount; ++i ){
			idx = i + this.ppCount * (this.page - 1);

			if( idx < photos2homepage.length ){
				this.images[ i ].img.src = this.imageHash[ idx ].src;
				this.images[ i ].link.href = photos2homepage[ idx ].url;
				this.images[ i ].link.title = photos2homepage[ idx ].title;

				this.images[ i ].li.style.display = '';
			}
			else
				this.images[ i ].li.style.display = 'none';
		}
	}
}
