jQuery(function ($) {
	if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
		$.get(LiveJournal.getAjaxUrl('controlstrip'), { user: Site.currentJournal }, function (data) {
				$(data).appendTo(document.body).ljAddContextualPopup();
			}
		);
	}

    // add placeholders for login, password and search fields
    $('#lj_controlstrip_new input[placeholder]').labeledPlaceholder();

    // community filter functionality
    if ( Site.remoteUser ) {
        (function () {
            var bubble,
                form,
                input,
                submit;

            bubble = $('#lj_controlstrip_new .w-cs-filter-inner');

            // exit if filter content is not currently on the page
            if ( bubble.length === 0 ) {
                return;
            }

            form = $('#sortByPoster');
            input = form.find('[name=poster]');
            submit = form.find('[type=image]');

            bubble.bubble({
                target: '#lj_controlstrip_new .w-cs-filter-icon',
                showOn: 'click',
                closeControl: false
            });

            input.input(function () {
                if( this.value.length ) {
                    submit.css('opacity', 1)
                        .prop( 'disabled', false );
                } else {
                    submit.css('opacity', 0)
                        .prop( 'disabled', true );
                }
            });

            form.on('submit', function (e) {
                if( !input.val().length ) {
                    e.preventDefault();
                }
            });
        }());
    }

});
