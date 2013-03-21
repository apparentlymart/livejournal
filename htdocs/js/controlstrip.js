;(function ($) {
    'use strict';

    /**
     * Add community filter functionality for control strip
     */
    function addFilterFunctionality() {
        var bubble,
            form,
            input,
            submit;

        // filter is available only for logged in users
        if ( !Site.remoteUser ) {
            return;
        }

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
                    .prop('disabled', false);
            } else {
                submit.css('opacity', 0)
                    .prop('disabled', true);
            }
        });

        form.on('submit', function (e) {
            if( !input.val().length ) {
                e.preventDefault();
            }
        });
    }

    /**
     * Add labled placeholders for the control strip
     */
    function addLabledPlaceholders() {
        $('#lj_controlstrip_new input[placeholder]').labeledPlaceholder();
    }

    $(function () {
        // load control strip if it's not available on document ready
        // Notice: use cases are not clear
        if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
            $.get(LiveJournal.getAjaxUrl('controlstrip'), { user: Site.currentJournal }, function (data) {
                    $(data).appendTo(document.body).ljAddContextualPopup();
                    addFilterFunctionality();
                    addLabledPlaceholders();
                }
            );
        } else {
            addLabledPlaceholders();
            addFilterFunctionality();
        }
    });

}(jQuery));
