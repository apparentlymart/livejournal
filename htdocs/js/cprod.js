// This library will provide handy functionality to a contextual prodding box on a page.
CProd =
{
	// show the next tip
	nextClick: function (node, e, data)
	{
		node.onclick = function(){ return false }
		
		var xhr = jQuery.getJSON(
			'/tools/endpoints/cprod.bml',
			jQuery.extend({content: 'framed'}, data),
			function(res)
			{
				jQuery(res.content).replaceAll('#CProd_box');
			}
		);
		
		jQuery(e).hourglass(xhr);
		
		return false;
	}
}
