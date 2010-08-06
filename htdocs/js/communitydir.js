jQuery(function(){
	jQuery('div.b-catalogue li > span')
	.click(function(e){
		e.preventDefault();
		jQuery(this).parent().toggleClass('m-section-item-open');
	});
});
