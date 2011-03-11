jQuery(document).delegate(".b-catalogue .m-switch", "click", function() {
	jQuery(this).closest("li").toggleClass("m-section-item-open");
});
