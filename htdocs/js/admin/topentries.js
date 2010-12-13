jQuery( function( $ ) {
	var CONFIG = {
		container: "#delete-posts",
		selectall: "li:first input[type=checkbox]",
		elements: "li:not(:first) input[type=checkbox]"
	}

	var container = $( CONFIG.container ),
		selectall = container.find( CONFIG.selectall ),
		elements = container.find( CONFIG.elements );

	function selectAllCheckboxes() {
		var checked = !!selectall.attr( 'checked' );
		elements.attr( 'checked', checked );
	}

	selectall.change( function() { setTimeout( selectAllCheckboxes, 0 ) } );
	elements.change( function() {
		if( !this.checked ) {
			selectall.attr( 'checked', false );
		}
	} );
} );
