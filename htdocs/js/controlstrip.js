jQuery(function($){
	!document.getElementById('lj_controlstrip') &&
		$.get(LiveJournal.getAjaxUrl('controlstrip'),
			{ user: Site.currentJournal },
			function(data)
			{
				$(data).appendTo(document.body).ljAddContextualPopup();
			}
		);
});
