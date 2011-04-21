jQuery(function ($) {
	if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
		$.get(LiveJournal.getAjaxUrl('controlstrip'), { user: Site.currentJournal }, function (data) {
				$(data).appendTo(document.body).ljAddContextualPopup();
			}
		);		
	}
});
