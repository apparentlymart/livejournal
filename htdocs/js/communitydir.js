jQuery(function(){
	jQuery('div.b-catalogue li > span')
	.click(function(e){
		e.preventDefault();
		jQuery(this).parents('li:first').toggleClass('m-section-item-open');
	});
});
