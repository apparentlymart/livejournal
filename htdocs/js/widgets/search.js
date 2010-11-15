jQuery(function($) {
	// remove for enable, see LJSUP-7052
	return;
	
	var label = $( '#search_text_label' ),
		search = $( '#search_text' );

	if( search.size() === 0 ){
		return;
	}

	search
		.focus( function(){
			label.hide();
		} )
		.blur( function(){
			if( search.val().length === 0 ){
				label.show();
			}
		} );

	if( search.val().length > 0 ){
		label.hide();
	}

	search.parents( 'form' ).submit( function( ev ){
		var val = $.trim( search.val() );
		if( val.length === 0 ){
			ev.preventDefault();
			return;
		}

		search.val ( val );
	} );

	//should feed tags array there
	tagAutocomplete( search, [] );

	function tagAutocomplete(node, tags)
	{
		jQuery(node).autocomplete({
			minLength: 1,
			source: function(request, response) {
				var tag = this.element.context.value;

				// delegate back to autocomplete, but extract term
				if (!tag) {
					response([]);
					return;
				}
				var resp_ary = [], i = -1;
				while (tags[++i]) {
					if (tags[i].indexOf(tag) === 0) {
						resp_ary.push(tags[i]);
						if (resp_ary.length === 10) {
							break;
						}
					}
				}
				
				response(resp_ary);
			},
			focus: function() {
				// prevent value inserted on focus
				return false;
			},
			select: function(e, ui) {
				this.value = ui.item.value;
				this.form.submit();
			},
			
			open: function()
			{
				var widget = jQuery(this).autocomplete('widget')
				// fix left pos in FF 3.6
				if (jQuery.browser.mozilla) {
					var offset = widget.offset();
					offset.left++;
					
					widget.offset(offset);
					widget.width(widget.width()+3);
				} else {
					widget.width(widget.width()+4);
				}
			}
		});
	}
} );
