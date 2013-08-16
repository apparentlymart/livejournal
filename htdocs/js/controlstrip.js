//= require js/jquery/jquery.calendarEvents.js
//= require js/jquery/jquery.lj.relations.js

/*global ContextualPopup */
/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Control strip functionality
 */
;(function ($) {
    'use strict';

    /**
     * Add community filter functionality for control strip
     */
    function initFilter() {
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

    /**
     * Initialize control strip
     */
    function init() {
        initFilter();
        addLabledPlaceholders();

        if ( LJ.Flags.isEnabled('friendsAndSubscriptions') ) {
            $('.w-cs-menu-friends-subscr').relations();

            LiveJournal.register_hook('relations.changed', function (event) {
                var data = event.data,
                    status = null;

                if (data.controlstrip_status) {
                    status = $('.js-controlstrip-status');

                    // Hide contextual popup before
                    // If you're trying to change status from contextual popup in control strip
                    if ( ContextualPopup.currentElement === status.find('.ljuser img').get(0) ) {
                        ContextualPopup.hide();
                    }

                    status
                        .html(data.controlstrip_status);
                }
            });
        }
    }

    $(function () {
        // load control strip if it's not available on document ready
        // Notice: some s2 users could turn off control strip for all users
        if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
            // fetch control strip from server
            $.get(
                LiveJournal.getAjaxUrl('controlstrip'),
                { user: Site.currentJournal },
                function (data) {
                    $(data).appendTo(document.body);
                    init();
                }
            );
        } else {
            init();
        }
    });

}(jQuery));
